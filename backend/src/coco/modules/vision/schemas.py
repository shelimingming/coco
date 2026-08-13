"""帮我看看：请求/响应 Schema。"""

from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class LookResponse(BaseModel):
    confidence: Literal["high", "low"]
    headline: str = ""
    detail: str
    safety_note: str = ""
    # 注入 Realtime 语音的详细读图文本（非直接 TTS）
    scene_description: str = ""
    # 历史会话 id；仅文本摘要入历史，不含图片
    conversation_id: UUID | None = None


class LookFollowUpRequest(BaseModel):
    conversation_id: UUID
    text: str = Field(..., min_length=1, max_length=500)


class LookFollowUpResponse(BaseModel):
    reply_text: str
    conversation_id: UUID
