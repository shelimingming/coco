"""日常提醒业务与 next_trigger_at 时区换算。"""

from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings
from coco.errors import AppError
from coco.models.reminder import (
    OccurrenceState,
    Reminder,
    ReminderCreatedSource,
    ReminderOccurrence,
    ReminderScheduleType,
    ReminderStatus,
)
from coco.models.user import User, UserRole
from coco.modules.reminders.schemas import (
    DelayRequest,
    OccurrenceResponse,
    ReminderCreateRequest,
    ReminderResponse,
    ReminderUpdateRequest,
)


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


def _to_response(reminder: Reminder) -> ReminderResponse:
    return ReminderResponse(
        id=reminder.id,
        title=reminder.title,
        schedule_type=reminder.schedule_type,
        schedule_time=reminder.schedule_time,
        status=reminder.status,
        created_source=reminder.created_source,
        next_trigger_at=reminder.next_trigger_at,
        created_at=reminder.created_at,
    )


def _occurrence_response(occ: ReminderOccurrence) -> OccurrenceResponse:
    return OccurrenceResponse(
        id=occ.id,
        reminder_id=occ.reminder_id,
        due_at=occ.due_at,
        state=occ.state,
        first_notified_at=occ.first_notified_at,
        second_notified_at=occ.second_notified_at,
        confirmed_at=occ.confirmed_at,
        escalated_at=occ.escalated_at,
    )


class ReminderService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def _tz(self) -> str:
        return self._settings.local_timezone

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
            }

        next_at = compute_next_trigger_at(
            body.schedule_time,
            schedule_type=body.schedule_type,
            tz_name=self._tz(),
        )
        reminder = Reminder(
            user_id=user.id,
            title=body.title.strip(),
            schedule_type=body.schedule_type,
            schedule_time=body.schedule_time,
            status=ReminderStatus.ACTIVE.value,
            created_source=created_source,
            next_trigger_at=next_at,
        )
        session.add(reminder)
        await session.commit()
        await session.refresh(reminder)
        return _to_response(reminder)

    async def list_for_user(self, session: AsyncSession, *, user: User) -> list[ReminderResponse]:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "reminder.parent_required", "只有老人模式可以查看提醒列表。")
        result = await session.execute(
            select(Reminder)
            .where(
                Reminder.user_id == user.id,
                Reminder.status != ReminderStatus.DELETED.value,
            )
            .order_by(Reminder.next_trigger_at.asc().nulls_last())
        )
        return [_to_response(r) for r in result.scalars().all()]

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
        if body.title is not None:
            reminder.title = body.title.strip()
        if body.schedule_type is not None:
            reminder.schedule_type = body.schedule_type
        if body.schedule_time is not None:
            reminder.schedule_time = body.schedule_time
        if body.status is not None:
            reminder.status = body.status
        if body.schedule_type is not None or body.schedule_time is not None:
            reminder.next_trigger_at = compute_next_trigger_at(
                reminder.schedule_time,
                schedule_type=reminder.schedule_type,
                tz_name=self._tz(),
            )
        await session.commit()
        await session.refresh(reminder)
        return _to_response(reminder)

    async def delete(
        self, session: AsyncSession, *, user: User, reminder_id: UUID
    ) -> dict[str, bool]:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "reminder.parent_required", "只有老人模式可以删除提醒。")
        reminder = await self.get_owned(session, user=user, reminder_id=reminder_id)
        reminder.status = ReminderStatus.DELETED.value
        reminder.next_trigger_at = None
        await session.commit()
        return {"ok": True}

    async def confirm_occurrence(
        self,
        session: AsyncSession,
        *,
        user: User,
        reminder_id: UUID,
        occurrence_id: UUID,
        user_confirmed: bool = True,
    ) -> OccurrenceResponse | dict:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "reminder.parent_required", "只有老人模式可以确认提醒。")
        if not user_confirmed:
            return {"status": "need_confirmation", "action": "confirm_reminder"}

        reminder = await self.get_owned(session, user=user, reminder_id=reminder_id)
        occ = await session.get(ReminderOccurrence, occurrence_id)
        if occ is None or occ.reminder_id != reminder.id:
            raise AppError(404, "reminder.occurrence_not_found", "找不到这条提醒记录。")
        if occ.state in {OccurrenceState.DONE.value, OccurrenceState.ESCALATED.value}:
            return _occurrence_response(occ)

        now = datetime.now(UTC)
        occ.state = OccurrenceState.DONE.value
        occ.confirmed_at = now

        if reminder.schedule_type == ReminderScheduleType.DAILY.value:
            reminder.next_trigger_at = compute_next_trigger_at(
                reminder.schedule_time,
                schedule_type=reminder.schedule_type,
                tz_name=self._tz(),
                after=now,
            )
        else:
            reminder.status = ReminderStatus.DONE.value
            reminder.next_trigger_at = None

        await session.commit()
        await session.refresh(occ)
        return _occurrence_response(occ)

    async def delay_occurrence(
        self,
        session: AsyncSession,
        *,
        user: User,
        reminder_id: UUID,
        occurrence_id: UUID,
        body: DelayRequest,
    ) -> OccurrenceResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "reminder.parent_required", "只有老人模式可以延后提醒。")
        reminder = await self.get_owned(session, user=user, reminder_id=reminder_id)
        occ = await session.get(ReminderOccurrence, occurrence_id)
        if occ is None or occ.reminder_id != reminder.id:
            raise AppError(404, "reminder.occurrence_not_found", "找不到这条提醒记录。")
        if occ.state in {OccurrenceState.DONE.value, OccurrenceState.ESCALATED.value}:
            raise AppError(
                400,
                "reminder.occurrence_closed",
                "这条提醒已经结束，不能再延后。",
            )

        # 延后：把当前 occurrence 标记完成，并重排 next_trigger
        now = datetime.now(UTC)
        occ.state = OccurrenceState.DONE.value
        occ.confirmed_at = now
        reminder.next_trigger_at = now + timedelta(minutes=body.minutes)
        # 一次性提醒延后后仍保持 ACTIVE，便于调度再次生成 occurrence
        if reminder.status == ReminderStatus.DONE.value:
            reminder.status = ReminderStatus.ACTIVE.value
        await session.commit()
        await session.refresh(occ)
        return _occurrence_response(occ)

    async def list_open_occurrences(
        self, session: AsyncSession, *, user: User
    ) -> list[OccurrenceResponse]:
        """当前用户尚未结束的到点记录（供语音 confirm 匹配）。"""
        result = await session.execute(
            select(ReminderOccurrence)
            .join(Reminder, Reminder.id == ReminderOccurrence.reminder_id)
            .where(
                Reminder.user_id == user.id,
                ReminderOccurrence.state.in_(
                    [
                        OccurrenceState.WAITING.value,
                        OccurrenceState.FIRST_REMINDER.value,
                        OccurrenceState.SECOND_REMINDER.value,
                    ]
                ),
            )
            .order_by(ReminderOccurrence.due_at.desc())
        )
        return [_occurrence_response(o) for o in result.scalars().all()]


def today_local_date(tz_name: str = "Asia/Shanghai") -> date:
    return datetime.now(UTC).astimezone(ZoneInfo(tz_name)).date()
