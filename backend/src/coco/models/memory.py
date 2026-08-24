"""用户主动要求记住的显式记忆。"""

from __future__ import annotations

import enum
import uuid

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from coco.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class MemoryCategory(enum.StrEnum):
    PROFILE = "PROFILE"
    FAMILY = "FAMILY"
    PREFERENCE = "PREFERENCE"
    ROUTINE = "ROUTINE"


class MemorySource(enum.StrEnum):
    VOICE = "VOICE"
    PARENT = "PARENT"


class Memory(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """仅存放用户主动要求记住的内容；Mem0 隐式抽取不进此表。"""

    __tablename__ = "memories"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[str] = mapped_column(String(32), nullable=False)
    source: Mapped[str] = mapped_column(String(16), nullable=False)
