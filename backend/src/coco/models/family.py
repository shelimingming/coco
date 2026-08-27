"""家庭与邀请码模型：MVP 固定 1 父母 + 1 主要子女。"""

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
    # 已解除绑定：保留 family_messages 等历史，用户 id 已清空
    DISSOLVED = "dissolved"


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

    # 8 字符链接令牌（不再口述）；明文存储，永不过期直至绑定成功
    code: Mapped[str] = mapped_column(String(8), nullable=False, index=True)
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
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
