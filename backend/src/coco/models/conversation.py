"""父母端语音对话历史：存最终转写与工具调用，不同步子女。"""

from __future__ import annotations

import enum
import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from coco.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class ConversationStatus(enum.StrEnum):
    ACTIVE = "ACTIVE"
    CLOSED = "CLOSED"
    ERROR = "ERROR"


class ConversationChannel(enum.StrEnum):
    VOICE_REALTIME = "VOICE_REALTIME"
    # 帮我看看：单次识图，仅文本摘要，不含图片
    LOOK = "LOOK"


class ConversationItemKind(enum.StrEnum):
    USER = "USER"
    ASSISTANT = "ASSISTANT"
    TOOL = "TOOL"


class Conversation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "conversations"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=ConversationStatus.ACTIVE.value,
    )
    channel: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=ConversationChannel.VOICE_REALTIME.value,
    )
    # 通话结束后由 LLM 生成；失败时用预览文案兜底
    title: Mapped[str | None] = mapped_column(String(64), nullable=True)


class ConversationItem(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "conversation_items"
    __table_args__ = (
        UniqueConstraint(
            "conversation_id",
            "seq",
            name="uq_conversation_items_conversation_id_seq",
        ),
    )

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("coco.conversations.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    seq: Mapped[int] = mapped_column(Integer, nullable=False)
    kind: Mapped[str] = mapped_column(String(16), nullable=False)
    # 对话正文；TOOL 可为空
    text: Mapped[str | None] = mapped_column(Text, nullable=True)
    tool_name: Mapped[str | None] = mapped_column(String(64), nullable=True)
    arguments_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    result_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    # 给父母看的通俗说明，避免展示原始 JSON
    display_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
