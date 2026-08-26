"""家庭与邀请链接模型：MVP 固定 1 父母 + 1 主要子女。"""

from __future__ import annotations

import enum
import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from coco.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class FamilyStatus(enum.StrEnum):
    ACTIVE = "active"
    # 任一方已创建家庭，对侧尚未加入
    PENDING = "pending"


class Family(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "families"

    # 双向邀请：pending 时父母/子女可仅填一侧
    parent_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        nullable=True,
        unique=True,
    )
    child_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="SET NULL"),
        nullable=True,
        unique=True,
    )
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=FamilyStatus.PENDING.value,
    )


class FamilyInvite(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "family_invites"

    # URL-safe 链接 token，对外分享用
    token: Mapped[str] = mapped_column(String(64), nullable=False, unique=True, index=True)
    inviter_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        nullable=False,
    )
    family_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.families.id", ondelete="CASCADE"),
        nullable=False,
    )
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
