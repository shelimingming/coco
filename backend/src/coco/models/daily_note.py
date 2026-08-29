"""每日小记：父母图文日记设置、正文与配图（BYTEA）。"""

from __future__ import annotations

import enum
import uuid
from datetime import date, datetime
from typing import Any

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from coco.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class DailyNoteStatus(enum.StrEnum):
    PENDING = "pending"
    READY = "ready"
    FAILED = "failed"
    EMPTY = "empty"


class DailyNoteSource(enum.StrEnum):
    AUTO = "auto"
    MANUAL = "manual"


class DailyNoteSettings(TimestampMixin, Base):
    """每父母一行：是否自动生成、是否生成后发给子女。"""

    __tablename__ = "daily_note_settings"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    generate_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    share_to_child_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    # 预留；MVP 固定按 20 点调度
    generate_hour: Mapped[int] = mapped_column(Integer, nullable=False, default=20)


class DailyNote(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "daily_notes"
    __table_args__ = (
        UniqueConstraint(
            "parent_id",
            "note_date",
            name="uq_daily_notes_parent_id_note_date",
        ),
    )

    parent_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    note_date: Mapped[date] = mapped_column(Date, nullable=False)
    # 1–3 条短句
    items_json: Mapped[list[Any]] = mapped_column(JSONB, nullable=False, default=list)
    body_text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=DailyNoteStatus.PENDING.value,
    )
    source: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=DailyNoteSource.MANUAL.value,
    )
    shared_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    share_error: Mapped[str | None] = mapped_column(Text, nullable=True)


class DailyNoteImage(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "daily_note_images"

    daily_note_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.daily_notes.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    seq: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    mime_type: Mapped[str] = mapped_column(String(64), nullable=False, default="image/png")
    data: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    # 审计用，截断后写入
    prompt: Mapped[str | None] = mapped_column(Text, nullable=True)
