"""家庭绑定请求 / 响应。"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class FamilyInviteCreateResponse(BaseModel):
    code: str
    expires_at: datetime
    family_id: UUID


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
