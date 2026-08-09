"""用户确认后的长期记忆。"""

from __future__ import annotations

import enum
import uuid

from sqlalchemy import Boolean, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from coco.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class MemoryCategory(enum.StrEnum):
    PROFILE = "PROFILE"
    FAMILY = "FAMILY"
    PREFERENCE = "PREFERENCE"
    ROUTINE = "ROUTINE"


class MemorySource(enum.StrEnum):
    PARENT = "PARENT"
    VOICE = "VOICE"


class Memory(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "memories"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[str] = mapped_column(String(32), nullable=False)
    source: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=MemorySource.PARENT.value,
    )
    # 仅 confirmed=true 才有长期价值；未确认不落库
    confirmed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
