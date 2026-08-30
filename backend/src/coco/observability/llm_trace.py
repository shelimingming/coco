"""大模型调用落库：独立 session，失败吞掉，不影响用户路径。"""

from __future__ import annotations

import logging
import re
from contextlib import contextmanager
from contextvars import ContextVar, Token
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from coco.models.llm_trace import LlmTrace

logger = logging.getLogger(__name__)

_MAX_STRING = 64 * 1024
_DATA_URL_RE = re.compile(r"^data:([^;,]+)?(;base64)?,", re.IGNORECASE)

_user_id: ContextVar[UUID | None] = ContextVar("llm_trace_user_id", default=None)
_conversation_id: ContextVar[UUID | None] = ContextVar("llm_trace_conversation_id", default=None)

PURPOSE_VOICE_SESSION = "voice_session"
PURPOSE_VOICE_TURN = "voice_turn"
PURPOSE_VOICE_TOOL = "voice_tool"
PURPOSE_VISION_LOOK = "vision_look"
PURPOSE_VISION_FOLLOW_UP = "vision_follow_up"
PURPOSE_VISION_INJECT = "vision_inject"
PURPOSE_IMAGE_GENERATE = "image_generate"
PURPOSE_TEXT_TITLE = "text_title"
PURPOSE_TEXT_TRANSLATE = "text_translate"
PURPOSE_TEXT_WEB_SEARCH = "text_web_search"
PURPOSE_TEXT_DAILY_NOTE = "text_daily_note"
PURPOSE_TEXT_DAILY_NOTE_EXTRACT = "text_daily_note_extract"
PURPOSE_TEXT_DAILY_NOTE_WRITE = "text_daily_note_write"
PURPOSE_MEM0_EXTRACT = "mem0_extract"
PURPOSE_MEM0_SEARCH = "mem0_search"


def bind_llm_trace(
    *,
    user_id: UUID | None = None,
    conversation_id: UUID | None = None,
) -> tuple[Token[UUID | None], Token[UUID | None]]:
    """在业务入口绑定当前用户/会话，供适配层写入时自动带上。"""
    return (
        _user_id.set(user_id),
        _conversation_id.set(conversation_id),
    )


def reset_llm_trace(tokens: tuple[Token[UUID | None], Token[UUID | None]]) -> None:
    _user_id.reset(tokens[0])
    _conversation_id.reset(tokens[1])


@contextmanager
def llm_trace_scope(*, user_id: UUID | None = None, conversation_id: UUID | None = None):
    tokens = bind_llm_trace(user_id=user_id, conversation_id=conversation_id)
    try:
        yield
    finally:
        reset_llm_trace(tokens)


def _truncate_str(value: str) -> str:
    if len(value) <= _MAX_STRING:
        return value
    return value[:_MAX_STRING] + f"…<truncated, total={len(value)}>"


def _redact_data_url(value: str) -> dict[str, Any] | str:
    match = _DATA_URL_RE.match(value)
    if not match:
        return _truncate_str(value)
    mime = (match.group(1) or "application/octet-stream").strip()
    comma = value.find(",")
    payload = value[comma + 1 :] if comma >= 0 else ""
    return {"omitted": True, "bytes": len(payload), "mime": mime}


def sanitize_payload(value: Any) -> Any:
    """去掉密钥、图片 data URL、音频块；长字符串截断。"""
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        lowered = value.lower()
        if "sk-" in value or "api_key" in lowered:
            return "<redacted>"
        return _redact_data_url(value)
    if isinstance(value, dict):
        out: dict[str, Any] = {}
        for key, item in value.items():
            key_l = str(key).lower()
            if any(token in key_l for token in ("api_key", "authorization", "secret", "token")):
                out[str(key)] = "<redacted>"
                continue
            if key_l in {"audio", "delta", "pcm"} and isinstance(item, str) and len(item) > 64:
                out[str(key)] = {"omitted": True, "bytes": len(item)}
                continue
            if key_l in {"image_url", "url"} and isinstance(item, str):
                out[str(key)] = _redact_data_url(item)
                continue
            if key_l == "image_url" and isinstance(item, dict):
                nested = dict(item)
                if isinstance(nested.get("url"), str):
                    nested["url"] = _redact_data_url(nested["url"])
                out[str(key)] = sanitize_payload(nested)
                continue
            out[str(key)] = sanitize_payload(item)
        return out
    if isinstance(value, list):
        return [sanitize_payload(item) for item in value]
    return str(value)


def usage_from_openai(data: dict[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(data, dict):
        return None
    usage = data.get("usage")
    if not isinstance(usage, dict):
        return None
    return {
        "prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": usage.get("completion_tokens"),
        "total_tokens": usage.get("total_tokens"),
    }


def _trace_enabled() -> bool:
    try:
        from coco.config import get_settings

        return bool(get_settings().llm_trace_enabled)
    except Exception:
        return False


def _session_factory_or_none():
    # 未 init_database 时不连库，避免单测无 DB 被拖进 Postgres
    from coco import database

    return database._session_factory


async def record_llm_trace(
    *,
    purpose: str,
    modality: str,
    model: str,
    status: str,
    provider: str = "dashscope",
    latency_ms: int | None = None,
    request_json: Any | None = None,
    response_json: Any | None = None,
    usage_json: dict[str, Any] | None = None,
    error_message: str | None = None,
    user_id: UUID | None = None,
    conversation_id: UUID | None = None,
    started_at: datetime | None = None,
) -> None:
    """写入一条调试记录；任何异常只打日志。"""
    if not _trace_enabled():
        return
    factory = _session_factory_or_none()
    if factory is None:
        return
    resolved_user = user_id if user_id is not None else _user_id.get()
    resolved_conversation = (
        conversation_id if conversation_id is not None else _conversation_id.get()
    )
    try:
        async with factory() as session:
            session.add(
                LlmTrace(
                    user_id=resolved_user,
                    conversation_id=resolved_conversation,
                    purpose=purpose,
                    modality=modality,
                    provider=provider,
                    model=model,
                    status=status,
                    latency_ms=latency_ms,
                    request_json=sanitize_payload(request_json)
                    if request_json is not None
                    else None,
                    response_json=sanitize_payload(response_json)
                    if response_json is not None
                    else None,
                    usage_json=sanitize_payload(usage_json) if usage_json is not None else None,
                    error_message=_truncate_str(error_message) if error_message else None,
                    started_at=started_at or datetime.now(UTC),
                )
            )
            await session.commit()
    except Exception:
        logger.warning("llm_trace_record_failed purpose=%s", purpose, exc_info=True)
