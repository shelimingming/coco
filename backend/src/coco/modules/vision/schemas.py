"""帮我看看：请求/响应 Schema。"""

from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel


class LookResponse(BaseModel):
    confidence: Literal["high", "low"]
    headline: str = ""
    detail: str
    safety_note: str = ""
    # 历史会话 id；仅文本摘要入历史，不含图片
    conversation_id: UUID | None = None
