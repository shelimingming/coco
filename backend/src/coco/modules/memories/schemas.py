"""记忆请求 / 响应。"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class MemoryCreateRequest(BaseModel):
    content: str = Field(min_length=1, max_length=2000)
    category: str = Field(pattern="^(PROFILE|FAMILY|PREFERENCE|ROUTINE)$")
    # 只有用户确认后才写入；false 时返回 need_confirmation
    user_confirmed: bool = True


class MemoryResponse(BaseModel):
    id: UUID
    content: str
    category: str
    source: str
    confirmed: bool
    created_at: datetime
    updated_at: datetime
