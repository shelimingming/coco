"""记忆请求 / 响应（Mem0 代理，无本地表字段）。"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class MemoryResponse(BaseModel):
    id: str
    content: str
    created_at: datetime | None = None
    updated_at: datetime | None = None
