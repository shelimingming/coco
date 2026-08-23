"""大模型调试落库：脱敏与失败不打断主路径。"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from coco.observability.llm_trace import (
    PURPOSE_TEXT_TITLE,
    record_llm_trace,
    sanitize_payload,
)


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
