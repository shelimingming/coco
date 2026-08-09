"""日常提醒与到点发生记录。"""

from __future__ import annotations

import enum
import uuid
from datetime import datetime, time

from sqlalchemy import DateTime, ForeignKey, String, Time
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from coco.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class ReminderScheduleType(enum.StrEnum):
    ONCE = "ONCE"
    DAILY = "DAILY"


class ReminderStatus(enum.StrEnum):
    ACTIVE = "ACTIVE"
    PAUSED = "PAUSED"
    DONE = "DONE"
    DELETED = "DELETED"


class ReminderCreatedSource(enum.StrEnum):
    PARENT = "PARENT"
    VOICE = "VOICE"


class OccurrenceState(enum.StrEnum):
    WAITING = "WAITING"
    FIRST_REMINDER = "FIRST_REMINDER"
    SECOND_REMINDER = "SECOND_REMINDER"
    DONE = "DONE"
    ESCALATED = "ESCALATED"


class Reminder(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "reminders"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    schedule_type: Mapped[str] = mapped_column(String(16), nullable=False)
    # 本地时区（MVP 固定 Asia/Shanghai）下的时刻
    schedule_time: Mapped[time] = mapped_column(Time, nullable=False)
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=ReminderStatus.ACTIVE.value,
    )
    created_source: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=ReminderCreatedSource.PARENT.value,
    )
    # UTC，调度器按此扫描 due
    next_trigger_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        index=True,
    )


class ReminderOccurrence(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """一次到点对应一条记录，状态机落在此表避免每日提醒历史被覆盖。"""

    __tablename__ = "reminder_occurrences"

    reminder_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.reminders.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    state: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=OccurrenceState.WAITING.value,
        index=True,
    )
    first_notified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    second_notified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    escalated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
