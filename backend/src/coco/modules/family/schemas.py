"""家庭绑定请求 / 响应。"""

from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, Field

from coco.models.user import UserRole


class FamilyInviteCreateResponse(BaseModel):
    token: str
    invite_url: str
    family_id: UUID


class FamilyInvitePreviewResponse(BaseModel):
    """免鉴权预览：被邀请方打开链接时展示。"""

    inviter_display_name: str
    # 被邀请方应使用的登录角色
    target_role: UserRole
    valid: bool = True


class FamilyJoinRequest(BaseModel):
    token: str = Field(min_length=8, max_length=64)


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
