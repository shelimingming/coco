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


class ReminderSuggestionCreateRequest(BaseModel):
    """子女为父母创建的提醒建议（须父母确认后才调度）。"""

    title: str = Field(min_length=1, max_length=200)
    schedule_type: str = Field(pattern="^(ONCE|DAILY)$")
    schedule_time: time


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
    suggested_by_user_id: UUID | None = None
    suggested_by_display_name: str | None = None
    timing_mode: str = "EXACT"
    allowed_delay_minutes: int = 15
    escalation_policy: str = "NONE"
    revision: int = 1


class OccurrenceResponse(BaseModel):
    id: UUID
    reminder_id: UUID
    due_at: datetime
    delivery_state: str
    response_status: str
    reminder_revision: int
    title_snapshot: str
    snooze_until: datetime | None
    attempt_count: int
    response_source: str
    first_notified_at: datetime | None
    second_notified_at: datetime | None
    confirmed_at: datetime | None
    escalated_at: datetime | None


class OccurrenceRespondRequest(BaseModel):
    status: str = Field(
        pattern="^(COMPLETED_SELF_REPORTED|SKIPPED_SELF_REPORTED|SNOOZED|UNANSWERED)$"
    )
    snooze_minutes: int | None = Field(default=None, ge=5, le=180)
    source: str = Field(default="BUTTON", pattern="^(VOICE|BUTTON|NONE)$")
