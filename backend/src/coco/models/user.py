"""用户模型。"""

from __future__ import annotations

import enum

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from coco.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class UserRole(enum.StrEnum):
    PARENT = "parent"
    CHILD = "child"


class UserStatus(enum.StrEnum):
    ACTIVE = "active"
    DISABLED = "disabled"


class User(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "users"

    # phone_hash 用于查重 / OTP；phone_e164 明文供绑定子女拨打（登录时写入）
    phone_hash: Mapped[str] = mapped_column(String(128), unique=True, nullable=False)
    phone_masked: Mapped[str] = mapped_column(String(32), nullable=False)
    phone_e164: Mapped[str | None] = mapped_column(String(20), nullable=True)
    display_name: Mapped[str] = mapped_column(String(64), nullable=False)
    role: Mapped[str] = mapped_column(String(16), nullable=False, default=UserRole.PARENT.value)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default=UserStatus.ACTIVE.value)
