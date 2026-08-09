"""提醒到点调度：扫描 due、推进状态机、写通知。

状态推进逻辑写成纯函数便于单测；多实例用 SKIP LOCKED 避免重复触发。
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from coco.config import Settings
from coco.models.family import Family, FamilyStatus
from coco.models.notification import Notification, NotificationType
from coco.models.reminder import (
    OccurrenceState,
    Reminder,
    ReminderOccurrence,
    ReminderScheduleType,
    ReminderStatus,
)
from coco.modules.reminders.service import compute_next_trigger_at

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class OccurrenceTransition:
    next_state: str | None
    notify_parent: bool = False
    notify_child: bool = False
    set_first_notified: bool = False
    set_second_notified: bool = False
    set_escalated: bool = False


def plan_occurrence_transition(
    *,
    state: str,
    now: datetime,
    first_notified_at: datetime | None,
    second_notified_at: datetime | None,
    second_delay: timedelta,
    escalate_delay: timedelta,
) -> OccurrenceTransition:
    """根据当前状态与时间决定下一步；无变化返回 next_state=None。"""
    if state == OccurrenceState.WAITING.value:
        return OccurrenceTransition(
            next_state=OccurrenceState.FIRST_REMINDER.value,
            notify_parent=True,
            set_first_notified=True,
        )
    if state == OccurrenceState.FIRST_REMINDER.value:
        if first_notified_at is None:
            return OccurrenceTransition(
                next_state=OccurrenceState.FIRST_REMINDER.value,
                notify_parent=True,
                set_first_notified=True,
            )
        if now >= first_notified_at + second_delay:
            return OccurrenceTransition(
                next_state=OccurrenceState.SECOND_REMINDER.value,
                notify_parent=True,
                set_second_notified=True,
            )
        return OccurrenceTransition(next_state=None)
    if state == OccurrenceState.SECOND_REMINDER.value:
        if second_notified_at is None:
            return OccurrenceTransition(
                next_state=OccurrenceState.SECOND_REMINDER.value,
                notify_parent=True,
                set_second_notified=True,
            )
        if now >= second_notified_at + escalate_delay:
            return OccurrenceTransition(
                next_state=OccurrenceState.ESCALATED.value,
                notify_child=True,
                set_escalated=True,
            )
        return OccurrenceTransition(next_state=None)
    return OccurrenceTransition(next_state=None)


async def create_due_occurrences(session: AsyncSession, *, now: datetime) -> int:
    """为已到点的 ACTIVE 提醒创建 WAITING occurrence，并清空/推进 next_trigger。"""
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
        session.add(
            ReminderOccurrence(
                reminder_id=reminder.id,
                due_at=due_at,
                state=OccurrenceState.WAITING.value,
            )
        )
        # 先清空，避免本轮未推进时下一轮重复创建；每日提醒在 escalate/confirm 后再排
        if reminder.schedule_type == ReminderScheduleType.DAILY.value:
            # 预排下一轮，当前 occurrence 独立推进
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
        .where(
            ReminderOccurrence.state.in_(
                [
                    OccurrenceState.WAITING.value,
                    OccurrenceState.FIRST_REMINDER.value,
                    OccurrenceState.SECOND_REMINDER.value,
                ]
            )
        )
        .with_for_update(skip_locked=True, of=ReminderOccurrence)
    )
    rows = list(result.all())
    changed = 0
    for occ, reminder in rows:
        plan = plan_occurrence_transition(
            state=occ.state,
            now=now,
            first_notified_at=occ.first_notified_at,
            second_notified_at=occ.second_notified_at,
            second_delay=second_delay,
            escalate_delay=escalate_delay,
        )
        if plan.next_state is None:
            continue

        occ.state = plan.next_state
        if plan.set_first_notified:
            occ.first_notified_at = now
        if plan.set_second_notified:
            occ.second_notified_at = now
        if plan.set_escalated:
            occ.escalated_at = now

        local_due = occ.due_at.astimezone()
        due_label = local_due.strftime("%H:%M")

        if plan.notify_parent:
            if plan.next_state == OccurrenceState.FIRST_REMINDER.value:
                body = f"到「{reminder.title}」时间了。已经做过了吗？"
            else:
                body = f"刚才的「{reminder.title}」提醒还没有确认。已经做过了吗？"
            session.add(
                Notification(
                    user_id=reminder.user_id,
                    type=NotificationType.REMINDER.value,
                    title="日常提醒",
                    body=body,
                    payload={
                        "reminder_id": str(reminder.id),
                        "occurrence_id": str(occ.id),
                        "state": occ.state,
                    },
                )
            )

        if plan.notify_child:
            # 措辞严格：只能描述未收到确认，不能说「没有吃药」
            child_body = f"今天 {due_label} 的「{reminder.title}」提醒经过两次提醒后仍未确认。"
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
                            "state": OccurrenceState.ESCALATED.value,
                        },
                    )
                )
            # 一次性提醒升级后标记 DONE，避免悬挂
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
    if created or advanced:
        logger.info(
            "scheduler_tick created_occurrences=%s advanced=%s",
            created,
            advanced,
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
