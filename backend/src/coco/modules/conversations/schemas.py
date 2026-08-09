"""对话历史请求 / 响应。"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class ConversationListItem(BaseModel):
    id: UUID
    started_at: datetime
    ended_at: datetime | None
    status: str
    channel: str
    # 结束时 LLM 生成；未生成时前端可回退 preview
    title: str | None
    # 列表预览：首条用户或助手话截断
    preview: str


class ConversationItemResponse(BaseModel):
    id: UUID
    seq: int
    kind: str
    text: str | None
    tool_name: str | None
    display_summary: str | None
    created_at: datetime


class ConversationDetailResponse(BaseModel):
    id: UUID
    started_at: datetime
    ended_at: datetime | None
    status: str
    channel: str
    title: str | None
    items: list[ConversationItemResponse]
