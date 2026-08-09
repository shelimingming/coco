"""报平安请求 / 响应。"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class MessagePreviewRequest(BaseModel):
    text: str = Field(min_length=1, max_length=1000)


class MessagePreviewResponse(BaseModel):
    original_text: str
    delivered_text: str
    translated: bool


class MessageSendRequest(BaseModel):
    original_text: str = Field(min_length=1, max_length=1000)
    delivered_text: str = Field(min_length=1, max_length=1000)


class FamilyMessageResponse(BaseModel):
    id: UUID
    family_id: UUID
    from_user_id: UUID
    to_user_id: UUID
    kind: str
    original_text: str
    delivered_text: str
    acknowledged_at: datetime | None
    created_at: datetime
