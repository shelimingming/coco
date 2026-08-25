"""日常提醒与到点发生记录。"""

from __future__ import annotations

import enum
import uuid
from datetime import datetime, time

from sqlalchemy import DateTime, ForeignKey, Integer, String, Time
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
    # 子女建议：父母确认前不调度
    PENDING_CONFIRM = "PENDING_CONFIRM"
    REJECTED = "REJECTED"


class ReminderCreatedSource(enum.StrEnum):
    PARENT = "PARENT"
    VOICE = "VOICE"
    CHILD = "CHILD"


class TimingMode(enum.StrEnum):
    """只影响通话中何时开口；本期服务端一律按 EXACT 投递。"""

    EXACT = "EXACT"
    FLEXIBLE = "FLEXIBLE"


class EscalationPolicy(enum.StrEnum):
    NONE = "NONE"
    FAMILY_AFTER_TWO_UNANSWERED = "FAMILY_AFTER_TWO_UNANSWERED"


class DeliveryState(enum.StrEnum):
    """调度器拥有：系统提示到第几次。"""

    PENDING = "PENDING"
    NOTIFIED_1 = "NOTIFIED_1"
    NOTIFIED_2 = "NOTIFIED_2"
    CLOSED = "CLOSED"


class ResponseStatus(enum.StrEnum):
    """用户拥有：老人怎么回应。UNANSWERED 仅由超时路径写入。"""

    NONE = "NONE"
    COMPLETED_SELF_REPORTED = "COMPLETED_SELF_REPORTED"
    SKIPPED_SELF_REPORTED = "SKIPPED_SELF_REPORTED"
    SNOOZED = "SNOOZED"
    UNANSWERED = "UNANSWERED"


class ResponseSource(enum.StrEnum):
    VOICE = "VOICE"
    BUTTON = "BUTTON"
    NONE = "NONE"


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
    # 子女建议时记录建议人；父母自建/语音创建为空
    suggested_by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    # UTC，调度器按此扫描 due；PENDING_CONFIRM 时必须为空
    next_trigger_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        index=True,
    )
    timing_mode: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=TimingMode.EXACT.value,
    )
    allowed_delay_minutes: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=15,
    )
    escalation_policy: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=EscalationPolicy.NONE.value,
    )
    # 改计划时加一；occurrence 冻结当时值，提示前比对
    revision: Mapped[int] = mapped_column(Integer, nullable=False, default=1)


class ReminderOccurrence(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """一次到点对应一条记录；投递进展与用户反馈拆成两个正交字段。"""

    __tablename__ = "reminder_occurrences"

    reminder_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.reminders.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    delivery_state: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=DeliveryState.PENDING.value,
        index=True,
    )
    response_status: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=ResponseStatus.NONE.value,
    )
    reminder_revision: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    title_snapshot: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    snooze_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    attempt_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    response_source: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=ResponseSource.NONE.value,
    )
    first_notified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    second_notified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    escalated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
