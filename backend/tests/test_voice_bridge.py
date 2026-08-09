"""实时语音桥接映射与能力开关单测（不打真实网络）。"""

from __future__ import annotations

import base64

from pydantic import SecretStr

from coco.config import Settings
from coco.modules.voice.service import map_vendor_event
from coco.providers.qwen_realtime import redact_realtime_event


def test_realtime_available_requires_api_key() -> None:
    without_key = Settings(
        _env_file=None,
        environment="test",
        aliyun_api_key=None,
    )
    with_key = Settings(
        _env_file=None,
        environment="test",
        aliyun_api_key=SecretStr("test-key"),
    )
    assert without_key.realtime_available is False
    assert with_key.realtime_available is True


def test_realtime_websocket_url_by_region() -> None:
    cn = Settings(_env_file=None, environment="test", aliyun_region="cn-beijing")
    intl = Settings(_env_file=None, environment="test", aliyun_region="ap-southeast-1")
    assert cn.realtime_websocket_url == "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
    assert intl.realtime_websocket_url == "wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime"


def test_map_vendor_speech_and_transcript_events() -> None:
    started, text = map_vendor_event({"type": "input_audio_buffer.speech_started"}, "")
    assert started == {"type": "speech.started"}
    assert text == ""

    stopped, text = map_vendor_event({"type": "input_audio_buffer.speech_stopped"}, "")
    assert stopped == {"type": "speech.stopped"}

    partial, text = map_vendor_event(
        {"type": "conversation.item.input_audio_transcription.delta", "delta": "你"},
        "",
    )
    assert partial == {"type": "user.partial", "text": "你"}
    assert text == ""

    final, text = map_vendor_event(
        {
            "type": "conversation.item.input_audio_transcription.completed",
            "transcript": "你好",
        },
        "",
    )
    assert final == {"type": "user.final", "text": "你好"}


def test_map_vendor_assistant_audio_and_final() -> None:
    audio_b64 = base64.b64encode(b"\x01\x02").decode("ascii")
    audio_event, text = map_vendor_event(
        {"type": "response.audio.delta", "delta": audio_b64},
        "嗨",
    )
    assert audio_event is not None
    assert audio_event["type"] == "assistant.audio"
    assert audio_event["audio"] == audio_b64
    assert audio_event["sample_rate"] == 24000
    assert text == "嗨"

    partial, text = map_vendor_event(
        {"type": "response.audio_transcript.delta", "delta": "呀"},
        "嗨",
    )
    assert partial == {"type": "assistant.partial", "text": "呀"}
    assert text == "嗨呀"

    done, text = map_vendor_event(
        {"type": "response.audio_transcript.done", "transcript": "嗨呀"},
        "嗨呀",
    )
    assert done == {"type": "assistant.final", "text": "嗨呀"}
    assert text == "嗨呀"


def test_map_vendor_ignores_unknown_events() -> None:
    mapped, text = map_vendor_event({"type": "session.created"}, "keep")
    assert mapped is None
    assert text == "keep"


def test_redact_realtime_event_hides_audio() -> None:
    audio_b64 = base64.b64encode(b"secret-audio").decode("ascii")
    redacted = redact_realtime_event({"type": "response.audio.delta", "delta": audio_b64})
    assert "secret-audio" not in str(redacted)
    assert "omitted" in redacted["delta"]
