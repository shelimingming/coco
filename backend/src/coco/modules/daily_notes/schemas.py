"""每日小记 API schema。"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict


class FrozenModel(BaseModel):
    model_config = ConfigDict(from_attributes=True, frozen=True)


class DailyNoteSettingsResponse(FrozenModel):
    generate_enabled: bool
    share_to_child_enabled: bool
    generate_hour: int
    gender: Literal["male", "female", "unknown"]
    has_parent_photo: bool
    # BOS 签名 URL，前端 Image.network 直连
    parent_photo_url: str | None = None


class DailyNoteSettingsUpdateRequest(BaseModel):
    generate_enabled: bool | None = None
    share_to_child_enabled: bool | None = None
    gender: Literal["male", "female", "unknown"] | None = None


class DailyNoteImageMeta(FrozenModel):
    id: uuid.UUID
    seq: int
    mime_type: str
    # BOS 签名 URL（完整 https）
    url: str


class DailyNoteResponse(FrozenModel):
    id: uuid.UUID
    note_date: date
    items: list[str]
    body_text: str
    status: str
    source: str
    shared_at: datetime | None
    images: list[DailyNoteImageMeta]
    created_at: datetime


class DailyNoteGenerateRequest(BaseModel):
    # 可选覆盖日期；默认今天（本地时区）
    note_date: date | None = None


class DailyNoteListResponse(FrozenModel):
    items: list[DailyNoteResponse]
