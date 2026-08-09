"""提醒请求 / 响应。"""

from __future__ import annotations

from datetime import datetime, time
from uuid import UUID

from pydantic import BaseModel, Field


class ReminderCreateRequest(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    schedule_type: str = Field(pattern="^(ONCE|DAILY)$")
    schedule_time: time
    # 语音工具调用时由服务端填 True；HTTP 创建视为用户已在 UI 确认
    user_confirmed: bool = True


class ReminderUpdateRequest(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    schedule_type: str | None = Field(default=None, pattern="^(ONCE|DAILY)$")
    schedule_time: time | None = None
    status: str | None = Field(default=None, pattern="^(ACTIVE|PAUSED)$")


class ReminderResponse(BaseModel):
    id: UUID
    title: str
    schedule_type: str
    schedule_time: time
    status: str
    created_source: str
    next_trigger_at: datetime | None
    created_at: datetime


class OccurrenceResponse(BaseModel):
    id: UUID
    reminder_id: UUID
    due_at: datetime
    state: str
    first_notified_at: datetime | None
    second_notified_at: datetime | None
    confirmed_at: datetime | None
    escalated_at: datetime | None


class DelayRequest(BaseModel):
    minutes: int = Field(default=30, ge=5, le=180)
