"""关怀摘要与子女今日状态。"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class CareShareCreateRequest(BaseModel):
    summary: str = Field(min_length=1, max_length=2000)
    urgency: str = Field(default="LOW", pattern="^(LOW|ATTENTION)$")
    reply_expectation: str = Field(
        default="WHEN_AVAILABLE",
        pattern="^(WHEN_AVAILABLE|SOON)$",
    )
    # 未经父母确认不得同步
    user_confirmed: bool = True


class CareShareResponse(BaseModel):
    id: UUID
    parent_id: UUID
    child_id: UUID
    summary: str
    urgency: str
    reply_expectation: str
    source: str
    parent_confirmed: bool
    read_at: datetime | None
    created_at: datetime


class ChildTodayReminderItem(BaseModel):
    title: str
    state: str
    due_at: datetime


class ChildTodayResponse(BaseModel):
    status: str  # NORMAL / ATTENTION / NEED_CONTACT
    headline: str
    attention_items: list[CareShareResponse]
    reminder_items: list[ChildTodayReminderItem]
    needs_contact_reason: str | None = None
