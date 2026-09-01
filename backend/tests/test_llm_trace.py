"""大模型调试落库：脱敏与失败不打断主路径。"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from coco.observability.llm_trace import (
    PURPOSE_TEXT_TITLE,
    normalize_usage,
    record_llm_trace,
    sanitize_payload,
    token_columns_from_usage,
    usage_from_openai,
    usage_from_realtime_event,
)


def test_normalize_usage_openai_shape() -> None:
    normalized = normalize_usage(
        {"prompt_tokens": 100, "completion_tokens": 40, "total_tokens": 140}
    )
    assert normalized == {
        "input_tokens": 100,
        "output_tokens": 40,
        "total_tokens": 140,
    }
    assert token_columns_from_usage(normalized) == (100, 40, 140)


def test_normalize_usage_realtime_shape() -> None:
    normalized = normalize_usage(
        {
            "input_tokens": 50,
            "output_tokens": 20,
            "total_tokens": 70,
            "input_tokens_details": {"text_tokens": 40, "audio_tokens": 10},
            "output_tokens_details": {"text_tokens": 5, "audio_tokens": 15},
        }
    )
    assert normalized is not None
    assert normalized["input_tokens"] == 50
    assert normalized["output_tokens"] == 20
    assert normalized["input_tokens_details"]["audio_tokens"] == 10


def test_usage_from_openai_normalizes() -> None:
    usage = usage_from_openai(
        {"usage": {"prompt_tokens": 12, "completion_tokens": 3, "total_tokens": 15}}
    )
    assert usage == {"input_tokens": 12, "output_tokens": 3, "total_tokens": 15}


def test_usage_from_realtime_event() -> None:
    usage = usage_from_realtime_event(
        {
            "type": "response.done",
            "response": {"usage": {"input_tokens": 8, "output_tokens": 2, "total_tokens": 10}},
        }
    )
    assert usage == {"input_tokens": 8, "output_tokens": 2, "total_tokens": 10}


def test_sanitize_payload_preserves_usage_token_fields() -> None:
    payload = {
        "prompt_tokens": 10,
        "completion_tokens": 5,
        "total_tokens": 15,
        "input_tokens": 10,
    }
    cleaned = sanitize_payload(payload)
    assert cleaned == payload


def test_sanitize_payload_redacts_images_and_audio() -> None:
    payload = {
        "api_key": "sk-secret",
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": "data:image/jpeg;base64,AAAA"},
                    }
                ],
            }
        ],
        "audio": "a" * 200,
    }
    cleaned = sanitize_payload(payload)
    assert cleaned["api_key"] == "<redacted>"
    url = cleaned["messages"][0]["content"][0]["image_url"]["url"]
    assert isinstance(url, dict)
    assert url["omitted"] is True
    assert "AAAA" not in str(cleaned)
    assert cleaned["audio"]["omitted"] is True
    assert cleaned["audio"]["bytes"] == 200


def test_sanitize_payload_truncates_long_strings() -> None:
    huge = "人" * 70_000
    cleaned = sanitize_payload({"text": huge})
    assert isinstance(cleaned["text"], str)
    assert len(cleaned["text"]) < 70_000
    assert "truncated" in cleaned["text"]


@pytest.mark.asyncio
async def test_record_llm_trace_swallows_errors(monkeypatch: pytest.MonkeyPatch) -> None:
    class BoomFactory:
        def __call__(self) -> object:
            raise RuntimeError("db down")

    monkeypatch.setattr(
        "coco.observability.llm_trace._trace_enabled",
        lambda: True,
    )
    monkeypatch.setattr(
        "coco.observability.llm_trace._session_factory_or_none",
        lambda: BoomFactory(),
    )
    await record_llm_trace(
        purpose=PURPOSE_TEXT_TITLE,
        modality="text",
        model="qwen-plus",
        status="ok",
        request_json={"text": "hello"},
        user_id=uuid4(),
        started_at=datetime.now(UTC),
    )


@pytest.mark.asyncio
async def test_record_llm_trace_skips_without_factory(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "coco.observability.llm_trace._trace_enabled",
        lambda: True,
    )
    monkeypatch.setattr(
        "coco.observability.llm_trace._session_factory_or_none",
        lambda: None,
    )
    await record_llm_trace(
        purpose=PURPOSE_TEXT_TITLE,
        modality="text",
        model="qwen-plus",
        status="skipped",
        error_message="未配置 API Key",
    )
