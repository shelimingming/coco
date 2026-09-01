"""大模型调用调试记录：只给运营后台看，不进 App、不进普通日志。"""

from __future__ import annotations

import enum
import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from coco.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class LlmTraceStatus(enum.StrEnum):
    OK = "ok"
    ERROR = "error"
    SKIPPED = "skipped"


class LlmTraceModality(enum.StrEnum):
    REALTIME = "realtime"
    TEXT = "text"
    VISION = "vision"
    IMAGE = "image"
    EMBEDDING = "embedding"


class LlmTrace(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "llm_traces"

    user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    conversation_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.conversations.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    # 见 record_llm_trace 的 purpose 约定
    purpose: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    modality: Mapped[str] = mapped_column(String(16), nullable=False)
    provider: Mapped[str] = mapped_column(String(32), nullable=False, default="dashscope")
    model: Mapped[str] = mapped_column(String(128), nullable=False)
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=LlmTraceStatus.OK.value,
        index=True,
    )
    latency_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # 归一化 token，便于 Admin 用量聚合；与 usage_json 同步写入
    input_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    output_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    total_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    request_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    response_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    usage_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
