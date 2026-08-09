"""登录相关请求 / 响应模型。"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from coco.models.user import UserRole


class FrozenModel(BaseModel):
    model_config = ConfigDict(from_attributes=True, frozen=True)


class PhoneCodeRequest(BaseModel):
    phone: str = Field(min_length=11, max_length=24)


class PhoneCodeResponse(FrozenModel):
    challenge_id: uuid.UUID
    expires_at: datetime
    is_registered: bool
    # 仅开发环境返回，方便前端自动填充
    dev_code: str | None = None


class PhoneLoginRequest(BaseModel):
    challenge_id: uuid.UUID
    phone: str = Field(min_length=11, max_length=24)
    code: str = Field(pattern=r"^\d{6}$")
    role: UserRole
    display_name: str | None = Field(default=None, max_length=64)
    device_id: str = Field(min_length=8, max_length=200)


class UserResponse(FrozenModel):
    id: uuid.UUID
    display_name: str
    role: UserRole
    phone_masked: str
    status: str


class AuthSessionResponse(FrozenModel):
    access_token: str
    refresh_token: str
    token_type: Literal["Bearer"] = "Bearer"
    expires_at: datetime
    refresh_expires_at: datetime
    user: UserResponse


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=200)
    device_id: str = Field(min_length=8, max_length=200)


class LogoutRequest(BaseModel):
    refresh_token: str | None = Field(default=None, max_length=200)
