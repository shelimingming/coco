"""家庭绑定请求 / 响应。"""

from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class FamilyInviteCreateResponse(BaseModel):
    code: str
    invite_url: str
    target_role: str
    inviter_display_name: str
    family_id: UUID


class FamilyInvitePreviewResponse(BaseModel):
    status: Literal["valid", "consumed", "not_found"]
    inviter_display_name: str | None = None
    target_role: str | None = None
    family_id: UUID | None = None


class FamilyJoinRequest(BaseModel):
    code: str = Field(min_length=6, max_length=8)


class FamilyResponse(BaseModel):
    id: UUID
    # pending 时可能只有一侧
    parent_user_id: UUID | None
    child_user_id: UUID | None
    status: str
    parent_display_name: str | None = None
    child_display_name: str | None = None
    # 仅子女视角返回；11 位国内号，用于一键拨打
    parent_phone: str | None = None
