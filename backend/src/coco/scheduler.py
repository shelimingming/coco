"""提醒到点调度：扫描 due、推进状态机、写通知。

状态推进逻辑写成纯函数便于单测；多实例用 SKIP LOCKED 避免重复触发。
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from coco.config import Settings
from coco.models.family import Family, FamilyStatus
from coco.models.notification import Notification, NotificationType
from coco.models.reminder import (
    DeliveryState,
    EscalationPolicy,
    Reminder,
    ReminderOccurrence,
    ReminderScheduleType,
    ReminderStatus,
    ResponseStatus,
)
from coco.modules.reminders.service import compute_next_trigger_at

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class OccurrenceTransition:
    next_delivery_state: str | None
    next_response_status: str | None = None
    notify_parent: bool = False
    notify_child: bool = False
    set_first_notified: bool = False
    set_second_notified: bool = False
    set_escalated: bool = False
    increment_attempt: bool = False
    clear_snooze: bool = False


def plan_occurrence_transition(
    *,
    delivery_state: str,
    now: datetime,
    first_notified_at: datetime | None,
    second_notified_at: datetime | None,
    snooze_until: datetime | None,
    reminder_revision: int,
    current_revision: int,
    escalation_policy: str,
    second_delay: timedelta,
    escalate_delay: timedelta,
) -> OccurrenceTransition:
    """根据投递进展与时间决定下一步；无变化返回 next_delivery_state=None。"""
    # 计划已改版：旧 occurrence 直接关闭，不再提示
    if reminder_revision != current_revision:
        return OccurrenceTransition(
            next_delivery_state=DeliveryState.CLOSED.value,
            next_response_status=ResponseStatus.NONE.value,
        )

    if delivery_state == DeliveryState.PENDING.value:
        if snooze_until is not None and snooze_until > now:
            return OccurrenceTransition(next_delivery_state=None)
        return OccurrenceTransition(
            next_delivery_state=DeliveryState.NOTIFIED_1.value,
            notify_parent=True,
            set_first_notified=True,
            increment_attempt=True,
            clear_snooze=True,
        )
    if delivery_state == DeliveryState.NOTIFIED_1.value:
        # 缺时间戳只补字段，绝不再发通知（否则每轮扫描刷屏）
        if first_notified_at is None:
            return OccurrenceTransition(
                next_delivery_state=DeliveryState.NOTIFIED_1.value,
                set_first_notified=True,
            )
        if now >= first_notified_at + second_delay:
            return OccurrenceTransition(
                next_delivery_state=DeliveryState.NOTIFIED_2.value,
                notify_parent=True,
                set_second_notified=True,
                increment_attempt=True,
            )
        return OccurrenceTransition(next_delivery_state=None)
    if delivery_state == DeliveryState.NOTIFIED_2.value:
        if second_notified_at is None:
            return OccurrenceTransition(
                next_delivery_state=DeliveryState.NOTIFIED_2.value,
                set_second_notified=True,
            )
        if now >= second_notified_at + escalate_delay:
            notify_child = (
                escalation_policy == EscalationPolicy.FAMILY_AFTER_TWO_UNANSWERED.value
            )
            return OccurrenceTransition(
                next_delivery_state=DeliveryState.CLOSED.value,
                next_response_status=ResponseStatus.UNANSWERED.value,
                notify_child=notify_child,
                set_escalated=notify_child,
            )
        return OccurrenceTransition(next_delivery_state=None)
    return OccurrenceTransition(next_delivery_state=None)


_OPEN_DELIVERY_STATES = (
    DeliveryState.PENDING.value,
    DeliveryState.NOTIFIED_1.value,
    DeliveryState.NOTIFIED_2.value,
)


async def _close_open_occurrences(
    session: AsyncSession,
    *,
    reminder_id: UUID,
    response_status: str = ResponseStatus.UNANSWERED.value,
) -> None:
    """收尾同一计划下未完结的到点，避免多日堆积叠弹。"""
    result = await session.execute(
        select(ReminderOccurrence).where(
            ReminderOccurrence.reminder_id == reminder_id,
            ReminderOccurrence.delivery_state.in_(_OPEN_DELIVERY_STATES),
        )
    )
    for occ in result.scalars().all():
        occ.delivery_state = DeliveryState.CLOSED.value
        occ.response_status = response_status
        occ.snooze_until = None


async def create_due_occurrences(session: AsyncSession, *, now: datetime) -> int:
    """为已到点的 ACTIVE 提醒创建 PENDING occurrence，并清空/推进 next_trigger。"""
    result = await session.execute(
        select(Reminder)
        .where(
            Reminder.status == ReminderStatus.ACTIVE.value,
            Reminder.next_trigger_at.is_not(None),
            Reminder.next_trigger_at <= now,
        )
        .with_for_update(skip_locked=True)
    )
    reminders = list(result.scalars().all())
    created = 0
    for reminder in reminders:
        due_at = reminder.next_trigger_at
        assert due_at is not None
        # 新一轮到点前关掉旧 occurrence，父母只需处理「这一次」
        await _close_open_occurrences(session, reminder_id=reminder.id)
        session.add(
            ReminderOccurrence(
                reminder_id=reminder.id,
                due_at=due_at,
                delivery_state=DeliveryState.PENDING.value,
                response_status=ResponseStatus.NONE.value,
                reminder_revision=reminder.revision,
                title_snapshot=reminder.title,
                attempt_count=0,
            )
        )
        # 先清空，避免本轮未推进时下一轮重复创建；每日提醒预排下一轮
        if reminder.schedule_type == ReminderScheduleType.DAILY.value:
            reminder.next_trigger_at = compute_next_trigger_at(
                reminder.schedule_time,
                schedule_type=reminder.schedule_type,
                after=due_at,
            )
        else:
            reminder.next_trigger_at = None
        created += 1
    if created:
        await session.commit()
    return created


async def advance_open_occurrences(
    session: AsyncSession,
    *,
    settings: Settings,
    now: datetime,
) -> int:
    second_delay = timedelta(minutes=settings.reminder_second_delay_minutes)
    escalate_delay = timedelta(minutes=settings.reminder_escalate_delay_minutes)

    result = await session.execute(
        select(ReminderOccurrence, Reminder)
        .join(Reminder, Reminder.id == ReminderOccurrence.reminder_id)
        .where(ReminderOccurrence.delivery_state.in_(_OPEN_DELIVERY_STATES))
        .with_for_update(skip_locked=True, of=ReminderOccurrence)
    )
    rows = list(result.all())
    changed = 0
    for occ, reminder in rows:
        # 计划已停用/删除：静默收尾，不再推通知
        if reminder.status != ReminderStatus.ACTIVE.value:
            occ.delivery_state = DeliveryState.CLOSED.value
            if occ.response_status == ResponseStatus.NONE.value:
                occ.response_status = ResponseStatus.UNANSWERED.value
            occ.snooze_until = None
            changed += 1
            continue

        plan = plan_occurrence_transition(
            delivery_state=occ.delivery_state,
            now=now,
            first_notified_at=occ.first_notified_at,
            second_notified_at=occ.second_notified_at,
            snooze_until=occ.snooze_until,
            reminder_revision=occ.reminder_revision,
            current_revision=reminder.revision,
            escalation_policy=reminder.escalation_policy,
            second_delay=second_delay,
            escalate_delay=escalate_delay,
        )
        if plan.next_delivery_state is None:
            continue

        occ.delivery_state = plan.next_delivery_state
        if plan.next_response_status is not None:
            occ.response_status = plan.next_response_status
        if plan.set_first_notified:
            occ.first_notified_at = now
        if plan.set_second_notified:
            occ.second_notified_at = now
        if plan.set_escalated:
            occ.escalated_at = now
        if plan.increment_attempt:
            occ.attempt_count += 1
        if plan.clear_snooze:
            occ.snooze_until = None

        local_due = occ.due_at.astimezone()
        due_label = local_due.strftime("%H:%M")
        title = occ.title_snapshot or reminder.title

        if plan.notify_parent:
            if plan.next_delivery_state == DeliveryState.NOTIFIED_1.value:
                body = "可可有一条提醒"
            else:
                body = "可可还有一条提醒没有确认"
            session.add(
                Notification(
                    user_id=reminder.user_id,
                    type=NotificationType.REMINDER.value,
                    title="可可有一条提醒",
                    body=body,
                    payload={
                        "reminder_id": str(reminder.id),
                        "occurrence_id": str(occ.id),
                        "title": title,
                        "delivery_state": occ.delivery_state,
                    },
                )
            )

        if plan.notify_child:
            # 措辞严格：只能描述未收到确认，不能说「没有吃药」
            child_body = f"今天 {due_label} 的「{title}」提醒经过两次提醒后仍未确认。"
            family = await session.scalar(
                select(Family).where(
                    Family.parent_user_id == reminder.user_id,
                    Family.status == FamilyStatus.ACTIVE.value,
                    Family.child_user_id.is_not(None),
                )
            )
            if family is not None and family.child_user_id is not None:
                session.add(
                    Notification(
                        user_id=family.child_user_id,
                        type=NotificationType.CARE_MESSAGE.value,
                        title="提醒未确认",
                        body=child_body,
                        payload={
                            "reminder_id": str(reminder.id),
                            "occurrence_id": str(occ.id),
                            "delivery_state": DeliveryState.CLOSED.value,
                            "response_status": ResponseStatus.UNANSWERED.value,
                        },
                    )
                )
            # 一次性提醒关闭后标记 DONE，避免悬挂
            if reminder.schedule_type == ReminderScheduleType.ONCE.value:
                reminder.status = ReminderStatus.DONE.value

        elif plan.next_delivery_state == DeliveryState.CLOSED.value:
            if reminder.schedule_type == ReminderScheduleType.ONCE.value:
                reminder.status = ReminderStatus.DONE.value

        changed += 1

    if changed:
        await session.commit()
    return changed


async def run_scheduler_tick(
    session_factory: async_sessionmaker[AsyncSession],
    settings: Settings,
) -> None:
    now = datetime.now(UTC)
    async with session_factory() as session:
        created = await create_due_occurrences(session, now=now)
        advanced = await advance_open_occurrences(session, settings=settings, now=now)
    # 每日小记与提醒解耦，独立 session，失败不影响提醒
    daily_done = 0
    try:
        from coco.modules.daily_notes.service import DailyNoteService

        async with session_factory() as session:
            daily_done = await DailyNoteService(settings).run_auto_generate_due(
                session, now=now
            )
    except Exception:
        logger.exception("daily_note_scheduler_failed")
    if created or advanced or daily_done:
        logger.info(
            "scheduler_tick created_occurrences=%s advanced=%s daily_notes=%s",
            created,
            advanced,
            daily_done,
        )


async def scheduler_loop(
    session_factory: async_sessionmaker[AsyncSession],
    settings: Settings,
    *,
    stop_event: asyncio.Event,
) -> None:
    interval = max(5, settings.reminder_scan_interval_seconds)
    logger.info("scheduler_started interval_seconds=%s", interval)
    while not stop_event.is_set():
        try:
            await run_scheduler_tick(session_factory, settings)
        except Exception:
            logger.exception("scheduler_tick_failed")
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=interval)
        except TimeoutError:
            continue
    logger.info("scheduler_stopped")
