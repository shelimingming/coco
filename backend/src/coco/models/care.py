"""关怀摘要与家庭留言（子女报平安）。"""

from __future__ import annotations

import enum
import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from coco.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class CareUrgency(enum.StrEnum):
    LOW = "LOW"
    ATTENTION = "ATTENTION"


class CareReplyExpectation(enum.StrEnum):
    WHEN_AVAILABLE = "WHEN_AVAILABLE"
    SOON = "SOON"


class CareSource(enum.StrEnum):
    PARENT_CONVERSATION = "PARENT_CONVERSATION"
    VOICE = "VOICE"


class FamilyMessageKind(enum.StrEnum):
    CHILD_STATUS = "CHILD_STATUS"
    PARENT_REPLY = "PARENT_REPLY"


class CareShare(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "care_shares"

    parent_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    summary: Mapped[str] = mapped_column(Text, nullable=False)
    urgency: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=CareUrgency.LOW.value,
    )
    reply_expectation: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=CareReplyExpectation.WHEN_AVAILABLE.value,
    )
    source: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=CareSource.PARENT_CONVERSATION.value,
    )
    # 未经父母确认不得同步
    parent_confirmed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class FamilyMessage(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "family_messages"

    family_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.families.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    from_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        nullable=False,
    )
    to_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        nullable=False,
    )
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    original_text: Mapped[str] = mapped_column(Text, nullable=False)
    delivered_text: Mapped[str] = mapped_column(Text, nullable=False)
    acknowledged_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
