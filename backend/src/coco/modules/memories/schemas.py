"""记忆请求 / 响应。"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class MemoryCreateRequest(BaseModel):
    content: str = Field(min_length=1, max_length=2000)
    category: str = Field(pattern="^(PROFILE|FAMILY|PREFERENCE|ROUTINE)$")
    # 手动创建须确认；语音 source=VOICE 时服务端忽略此字段直接落库
    user_confirmed: bool = True


class MemoryResponse(BaseModel):
    id: UUID
    content: str
    category: str
    source: str
    confirmed: bool
    created_at: datetime
    updated_at: datetime
