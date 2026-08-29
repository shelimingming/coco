"""日常提醒业务与 next_trigger_at 时区换算。"""

from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings
from coco.errors import AppError
from coco.models.family import FamilyStatus
from coco.models.notification import Notification, NotificationType
from coco.models.reminder import (
    DeliveryState,
    EscalationPolicy,
    Reminder,
    ReminderCreatedSource,
    ReminderOccurrence,
    ReminderScheduleType,
    ReminderStatus,
    ResponseStatus,
    TimingMode,
)
from coco.models.user import User, UserRole
from coco.modules.family.service import get_family
from coco.modules.reminders.schemas import (
    OccurrenceRespondRequest,
    OccurrenceResponse,
    ReminderCreateRequest,
    ReminderResponse,
    ReminderSuggestionCreateRequest,
    ReminderUpdateRequest,
)

# 标题命中这些词时，默认两次无回应后通知家人
_ESCALATION_KEYWORDS = (
    "吃药",
    "服药",
    "用药",
    "输液",
    "打针",
    "复诊",
    "复查",
    "检查",
    "就诊",
    "胰岛素",
    "血压",
    "血糖",
)

def infer_escalation_policy(title: str) -> str:
    """按标题关键词推断升级策略；不猜医疗语义之外的类型。"""
    text = title.strip()
    if any(keyword in text for keyword in _ESCALATION_KEYWORDS):
        return EscalationPolicy.FAMILY_AFTER_TWO_UNANSWERED.value
    return EscalationPolicy.NONE.value


def compute_next_trigger_at(
    schedule_time: time,
    *,
    schedule_type: str,
    now_utc: datetime | None = None,
    tz_name: str = "Asia/Shanghai",
    after: datetime | None = None,
) -> datetime:
    """把本地时刻换成下一次触发的 UTC 时间。

    after：若给定，取「严格晚于 after」的下一次（用于每日提醒推进）。
    """
    tz = ZoneInfo(tz_name)
    now = now_utc or datetime.now(UTC)
    if now.tzinfo is None:
        now = now.replace(tzinfo=UTC)
    local_now = now.astimezone(tz)
    base_local = after.astimezone(tz) if after is not None else local_now

    candidate_date = base_local.date()
    candidate = datetime.combine(candidate_date, schedule_time, tzinfo=tz)
    # 严格晚于参考点，避免同一分钟重复触发
    if candidate <= base_local:
        candidate = datetime.combine(candidate_date + timedelta(days=1), schedule_time, tzinfo=tz)

    if schedule_type == ReminderScheduleType.ONCE.value and after is not None:
        # ONCE 在确认/完成后不再排下一轮；此处仍返回候选供创建时使用
        pass

    return candidate.astimezone(UTC)


def _to_response(
    reminder: Reminder,
    *,
    suggested_by_display_name: str | None = None,
) -> ReminderResponse:
    return ReminderResponse(
        id=reminder.id,
        title=reminder.title,
        schedule_type=reminder.schedule_type,
        schedule_time=reminder.schedule_time,
        status=reminder.status,
        created_source=reminder.created_source,
        next_trigger_at=reminder.next_trigger_at,
        created_at=reminder.created_at,
        suggested_by_user_id=reminder.suggested_by_user_id,
        suggested_by_display_name=suggested_by_display_name,
        timing_mode=reminder.timing_mode,
        allowed_delay_minutes=reminder.allowed_delay_minutes,
        escalation_policy=reminder.escalation_policy,
        revision=reminder.revision,
    )


def _occurrence_response(occ: ReminderOccurrence) -> OccurrenceResponse:
    return OccurrenceResponse(
        id=occ.id,
        reminder_id=occ.reminder_id,
        due_at=occ.due_at,
        delivery_state=occ.delivery_state,
        response_status=occ.response_status,
        reminder_revision=occ.reminder_revision,
        title_snapshot=occ.title_snapshot,
        snooze_until=occ.snooze_until,
        attempt_count=occ.attempt_count,
        response_source=occ.response_source,
        first_notified_at=occ.first_notified_at,
        second_notified_at=occ.second_notified_at,
        confirmed_at=occ.confirmed_at,
        escalated_at=occ.escalated_at,
    )


def _schedule_label(schedule_type: str, schedule_time: time) -> str:
    hhmm = schedule_time.strftime("%H:%M")
    if schedule_type == ReminderScheduleType.DAILY.value:
        return f"每天 {hhmm}"
    return f"一次 {hhmm}"


def _will_notify_family(title: str) -> bool:
    return infer_escalation_policy(title) == EscalationPolicy.FAMILY_AFTER_TWO_UNANSWERED.value


def _close_once_reminder(reminder: Reminder) -> None:
    if reminder.schedule_type == ReminderScheduleType.ONCE.value:
        reminder.status = ReminderStatus.DONE.value
        reminder.next_trigger_at = None


class ReminderService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def _tz(self) -> str:
        return self._settings.local_timezone

    async def _display_name(self, session: AsyncSession, user_id: UUID | None) -> str | None:
        if user_id is None:
            return None
        user = await session.get(User, user_id)
        return user.display_name if user is not None else None

    async def _to_response_async(
        self, session: AsyncSession, reminder: Reminder
    ) -> ReminderResponse:
        name = await self._display_name(session, reminder.suggested_by_user_id)
        return _to_response(reminder, suggested_by_display_name=name)

    async def create(
        self,
        session: AsyncSession,
        *,
        user: User,
        body: ReminderCreateRequest,
        created_source: str = ReminderCreatedSource.PARENT.value,
    ) -> ReminderResponse | dict:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "reminder.parent_required", "只有老人模式可以创建提醒。")
        # 写操作必须经用户确认；语音工具可先以 false 探测
        if not body.user_confirmed:
            return {
                "status": "need_confirmation",
                "title": body.title,
                "schedule_type": body.schedule_type,
                "schedule_time": body.schedule_time.strftime("%H:%M"),
                "will_notify_family": _will_notify_family(body.title),
            }

        next_at = compute_next_trigger_at(
            body.schedule_time,
            schedule_type=body.schedule_type,
            tz_name=self._tz(),
        )
        title = body.title.strip()
        reminder = Reminder(
            user_id=user.id,
            title=title,
            schedule_type=body.schedule_type,
            schedule_time=body.schedule_time,
            status=ReminderStatus.ACTIVE.value,
            created_source=created_source,
            next_trigger_at=next_at,
            timing_mode=TimingMode.EXACT.value,
            allowed_delay_minutes=15,
            escalation_policy=infer_escalation_policy(title),
            revision=1,
        )
        session.add(reminder)
        await session.commit()
        await session.refresh(reminder)
        return await self._to_response_async(session, reminder)

    async def create_suggestion(
        self,
        session: AsyncSession,
        *,
        user: User,
        body: ReminderSuggestionCreateRequest,
    ) -> ReminderResponse:
        """子女为绑定父母创建建议；PENDING_CONFIRM 且不调度，等父母确认。"""
        if user.role != UserRole.CHILD.value:
            raise AppError(403, "reminder.child_required", "只有子女模式可以给父母设提醒建议。")

        family = await get_family(session, user)
        if (
            family is None
            or family.status != FamilyStatus.ACTIVE.value
            or family.child_user_id != user.id
            or family.parent_user_id is None
        ):
            raise AppError(
                403,
                "reminder.family_required",
                "需要先和父母完成家庭绑定，才能设置提醒。",
            )

        title = body.title.strip()
        reminder = Reminder(
            user_id=family.parent_user_id,
            title=title,
            schedule_type=body.schedule_type,
            schedule_time=body.schedule_time,
            status=ReminderStatus.PENDING_CONFIRM.value,
            created_source=ReminderCreatedSource.CHILD.value,
            suggested_by_user_id=user.id,
            next_trigger_at=None,
            timing_mode=TimingMode.EXACT.value,
            allowed_delay_minutes=15,
            escalation_policy=infer_escalation_policy(title),
            revision=1,
        )
        session.add(reminder)
        await session.flush()

        schedule_text = _schedule_label(body.schedule_type, body.schedule_time)
        session.add(
            Notification(
                user_id=family.parent_user_id,
                type=NotificationType.REMINDER_SUGGESTION.value,
                title="家人想帮您设一个提醒",
                body=f"{user.display_name} 建议：{reminder.title}（{schedule_text}）",
                payload={
                    "reminder_id": str(reminder.id),
                    "title": reminder.title,
                    "schedule_type": reminder.schedule_type,
                    "schedule_time": reminder.schedule_time.strftime("%H:%M:%S"),
                    "suggested_by_user_id": str(user.id),
                    "suggested_by_display_name": user.display_name,
                    "will_notify_family": reminder.escalation_policy
                    == EscalationPolicy.FAMILY_AFTER_TWO_UNANSWERED.value,
                },
            )
        )
        await session.commit()
        await session.refresh(reminder)
        return await self._to_response_async(session, reminder)

    async def list_suggestions_for_child(
        self, session: AsyncSession, *, user: User
    ) -> list[ReminderResponse]:
        """子女查看自己给父母建议过的提醒（含待确认/已生效/已拒绝）。"""
        if user.role != UserRole.CHILD.value:
            raise AppError(403, "reminder.child_required", "只有子女模式可以查看提醒建议。")

        result = await session.execute(
            select(Reminder)
            .where(
                Reminder.suggested_by_user_id == user.id,
                Reminder.created_source == ReminderCreatedSource.CHILD.value,
                Reminder.status != ReminderStatus.DELETED.value,
            )
            .order_by(Reminder.created_at.desc())
        )
        reminders = list(result.scalars().all())
        name = user.display_name
        return [_to_response(r, suggested_by_display_name=name) for r in reminders]

    async def _mark_suggestion_notifications_read(
        self, session: AsyncSession, *, parent_user_id: UUID, reminder_id: UUID
    ) -> None:
        """列表确认/拒绝时也清掉首页建议通知，避免重复落卡。"""
        now = datetime.now(UTC)
        result = await session.execute(
            select(Notification).where(
                Notification.user_id == parent_user_id,
                Notification.type == NotificationType.REMINDER_SUGGESTION.value,
                Notification.read_at.is_(None),
            )
        )
        for note in result.scalars().all():
            payload_id = str(note.payload.get("reminder_id", ""))
            if payload_id == str(reminder_id):
                note.read_at = now

    async def accept_suggestion(
        self, session: AsyncSession, *, user: User, reminder_id: UUID
    ) -> ReminderResponse:
        """父母确认子女建议 → ACTIVE 并开始调度。"""
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "reminder.parent_required", "只有老人模式可以确认提醒建议。")

        reminder = await self.get_owned(session, user=user, reminder_id=reminder_id)
        if reminder.status != ReminderStatus.PENDING_CONFIRM.value:
            raise AppError(
                400,
                "reminder.not_pending",
                "这个提醒已经处理过了，不用再确认。",
            )

        reminder.status = ReminderStatus.ACTIVE.value
        reminder.next_trigger_at = compute_next_trigger_at(
            reminder.schedule_time,
            schedule_type=reminder.schedule_type,
            tz_name=self._tz(),
        )
        await self._mark_suggestion_notifications_read(
            session, parent_user_id=user.id, reminder_id=reminder.id
        )
        await session.commit()
        await session.refresh(reminder)
        return await self._to_response_async(session, reminder)

    async def reject_suggestion(
        self, session: AsyncSession, *, user: User, reminder_id: UUID
    ) -> ReminderResponse:
        """父母拒绝子女建议 → REJECTED，并通知子女。"""
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "reminder.parent_required", "只有老人模式可以拒绝提醒建议。")

        reminder = await self.get_owned(session, user=user, reminder_id=reminder_id)
        if reminder.status != ReminderStatus.PENDING_CONFIRM.value:
            raise AppError(
                400,
                "reminder.not_pending",
                "这个提醒已经处理过了，不用再操作。",
            )

        reminder.status = ReminderStatus.REJECTED.value
        reminder.next_trigger_at = None
        await self._mark_suggestion_notifications_read(
            session, parent_user_id=user.id, reminder_id=reminder.id
        )

        if reminder.suggested_by_user_id is not None:
            session.add(
                Notification(
                    user_id=reminder.suggested_by_user_id,
                    type=NotificationType.CARE_MESSAGE.value,
                    title="长辈没有采用该提醒",
                    body=f"「{reminder.title}」没有生效，长辈选择了不用。",
                    payload={
                        "reminder_id": str(reminder.id),
                        "status": ReminderStatus.REJECTED.value,
                    },
                )
            )

        await session.commit()
        await session.refresh(reminder)
        return await self._to_response_async(session, reminder)

    async def list_for_user(self, session: AsyncSession, *, user: User) -> list[ReminderResponse]:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "reminder.parent_required", "只有老人模式可以查看提醒列表。")
        result = await session.execute(
            select(Reminder)
            .where(
                Reminder.user_id == user.id,
                Reminder.status.notin_(
                    [
                        ReminderStatus.DELETED.value,
                        ReminderStatus.REJECTED.value,
                    ]
                ),
            )
            .order_by(Reminder.next_trigger_at.asc().nulls_last())
        )
        reminders = list(result.scalars().all())
        out: list[ReminderResponse] = []
        for reminder in reminders:
            out.append(await self._to_response_async(session, reminder))
        return out

    async def get_owned(self, session: AsyncSession, *, user: User, reminder_id: UUID) -> Reminder:
        reminder = await session.get(Reminder, reminder_id)
        if (
            reminder is None
            or reminder.user_id != user.id
            or reminder.status == ReminderStatus.DELETED.value
        ):
            raise AppError(404, "reminder.not_found", "找不到这个提醒，可能已被删除。")
        return reminder

    async def update(
        self,
        session: AsyncSession,
        *,
        user: User,
        reminder_id: UUID,
        body: ReminderUpdateRequest,
    ) -> ReminderResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "reminder.parent_required", "只有老人模式可以修改提醒。")
        reminder = await self.get_owned(session, user=user, reminder_id=reminder_id)
        if reminder.status == ReminderStatus.PENDING_CONFIRM.value:
            raise AppError(
                400,
                "reminder.pending_confirm",
                "请先确认或拒绝这条建议，确认后再修改。",
            )
        changed = False
        if body.title is not None:
            reminder.title = body.title.strip()
            reminder.escalation_policy = infer_escalation_policy(reminder.title)
            changed = True
        if body.schedule_type is not None:
            reminder.schedule_type = body.schedule_type
            changed = True
        if body.schedule_time is not None:
            reminder.schedule_time = body.schedule_time
            changed = True
        if body.status is not None:
            reminder.status = body.status
            changed = True
        if body.schedule_type is not None or body.schedule_time is not None:
            reminder.next_trigger_at = compute_next_trigger_at(
                reminder.schedule_time,
                schedule_type=reminder.schedule_type,
                tz_name=self._tz(),
            )
        if changed:
            reminder.revision += 1
        await session.commit()
        await session.refresh(reminder)
        return await self._to_response_async(session, reminder)

    async def delete(
        self, session: AsyncSession, *, user: User, reminder_id: UUID
    ) -> dict[str, bool]:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "reminder.parent_required", "只有老人模式可以删除提醒。")
        reminder = await self.get_owned(session, user=user, reminder_id=reminder_id)
        reminder.status = ReminderStatus.DELETED.value
        reminder.next_trigger_at = None
        reminder.revision += 1
        # 删除后收尾未完结到点，并清掉对应未读，避免浮层关不掉
        await self._close_open_occurrences(session, reminder_id=reminder.id)
        await self._mark_reminder_notifications_read(
            session, user_id=user.id, reminder_id=reminder.id
        )
        await session.commit()
        return {"ok": True}

    async def _close_open_occurrences(
        self, session: AsyncSession, *, reminder_id: UUID
    ) -> None:
        result = await session.execute(
            select(ReminderOccurrence).where(
                ReminderOccurrence.reminder_id == reminder_id,
                ReminderOccurrence.delivery_state.in_(
                    [
                        DeliveryState.PENDING.value,
                        DeliveryState.NOTIFIED_1.value,
                        DeliveryState.NOTIFIED_2.value,
                    ]
                ),
            )
        )
        for occ in result.scalars().all():
            occ.delivery_state = DeliveryState.CLOSED.value
            if occ.response_status == ResponseStatus.NONE.value:
                occ.response_status = ResponseStatus.UNANSWERED.value
            occ.snooze_until = None

    async def _mark_occurrence_notifications_read(
        self, session: AsyncSession, *, user_id: UUID, occurrence_id: UUID
    ) -> None:
        now = datetime.now(UTC)
        result = await session.execute(
            select(Notification).where(
                Notification.user_id == user_id,
                Notification.read_at.is_(None),
                Notification.payload.contains({"occurrence_id": str(occurrence_id)}),
            )
        )
        for note in result.scalars().all():
            note.read_at = now

    async def _mark_reminder_notifications_read(
        self, session: AsyncSession, *, user_id: UUID, reminder_id: UUID
    ) -> None:
        now = datetime.now(UTC)
        result = await session.execute(
            select(Notification).where(
                Notification.user_id == user_id,
                Notification.read_at.is_(None),
                Notification.payload.contains({"reminder_id": str(reminder_id)}),
            )
        )
        for note in result.scalars().all():
            note.read_at = now

    async def respond_to_occurrence(
        self,
        session: AsyncSession,
        *,
        user: User,
        occurrence_id: UUID,
        body: OccurrenceRespondRequest,
        user_confirmed: bool = True,
    ) -> OccurrenceResponse | dict:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "reminder.parent_required", "只有老人模式可以回应提醒。")
        if not user_confirmed:
            return {"status": "need_confirmation", "action": "respond_to_reminder"}

        occ = await session.get(ReminderOccurrence, occurrence_id)
        if occ is None:
            raise AppError(404, "reminder.occurrence_not_found", "找不到这条提醒记录。")
        # 已删除的计划仍允许收尾本次到点，否则未读通知会卡住浮层
        reminder = await session.get(Reminder, occ.reminder_id)
        if reminder is None or reminder.user_id != user.id:
            raise AppError(404, "reminder.not_found", "找不到这个提醒，可能已被删除。")

        if occ.delivery_state == DeliveryState.CLOSED.value:
            await self._mark_occurrence_notifications_read(
                session, user_id=user.id, occurrence_id=occ.id
            )
            await session.commit()
            return _occurrence_response(occ)

        status = body.status
        source = body.source
        now = datetime.now(UTC)

        if status == ResponseStatus.COMPLETED_SELF_REPORTED.value:
            occ.delivery_state = DeliveryState.CLOSED.value
            occ.response_status = status
            occ.response_source = source
            occ.confirmed_at = now
            occ.snooze_until = None
            if reminder.status != ReminderStatus.DELETED.value:
                _close_once_reminder(reminder)
        elif status == ResponseStatus.SKIPPED_SELF_REPORTED.value:
            occ.delivery_state = DeliveryState.CLOSED.value
            occ.response_status = status
            occ.response_source = source
            occ.confirmed_at = now
            occ.snooze_until = None
            if reminder.status != ReminderStatus.DELETED.value:
                _close_once_reminder(reminder)
        elif status == ResponseStatus.SNOOZED.value:
            minutes = body.snooze_minutes if body.snooze_minutes is not None else 30
            occ.delivery_state = DeliveryState.PENDING.value
            occ.response_status = ResponseStatus.SNOOZED.value
            occ.response_source = source
            occ.snooze_until = now + timedelta(minutes=minutes)
            # 延后只动 occurrence，不改写计划的 next_trigger_at
        elif status == ResponseStatus.UNANSWERED.value:
            occ.delivery_state = DeliveryState.CLOSED.value
            occ.response_status = status
            occ.response_source = source
            occ.snooze_until = None
            if reminder.status != ReminderStatus.DELETED.value:
                _close_once_reminder(reminder)
        else:
            raise AppError(400, "reminder.invalid_response", "这个回应类型还不支持。")

        await self._mark_occurrence_notifications_read(
            session, user_id=user.id, occurrence_id=occ.id
        )
        await session.commit()
        await session.refresh(occ)
        return _occurrence_response(occ)

    async def list_open_occurrences(
        self, session: AsyncSession, *, user: User
    ) -> list[OccurrenceResponse]:
        """当前用户尚未结束的到点记录（供语音 respond 匹配）。"""
        result = await session.execute(
            select(ReminderOccurrence)
            .join(Reminder, Reminder.id == ReminderOccurrence.reminder_id)
            .where(
                Reminder.user_id == user.id,
                ReminderOccurrence.delivery_state.in_(
                    [
                        DeliveryState.PENDING.value,
                        DeliveryState.NOTIFIED_1.value,
                        DeliveryState.NOTIFIED_2.value,
                    ]
                ),
            )
            .order_by(ReminderOccurrence.due_at.desc())
        )
        return [_occurrence_response(o) for o in result.scalars().all()]


def today_local_date(tz_name: str = "Asia/Shanghai") -> date:
    return datetime.now(UTC).astimezone(ZoneInfo(tz_name)).date()
