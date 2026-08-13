"""实时语音桥接映射与能力开关单测（不打真实网络）。"""

from __future__ import annotations

import base64

from pydantic import SecretStr

from coco.config import Settings
from coco.modules.voice.service import is_recoverable_vendor_error, map_vendor_event
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


def test_map_vendor_error_uses_generic_parent_copy() -> None:
    mapped, text = map_vendor_event(
        {
            "type": "error",
            "error": {
                "type": "invalid_request_error",
                "code": "invalid_value",
                "message": "Cannot create response while another response is in progress.",
            },
        },
        "keep",
    )
    assert mapped is not None
    assert mapped["type"] == "error"
    assert mapped["code"] == "invalid_value"
    assert mapped["message"] == "语音服务暂时不可用，请稍后再试。"
    assert text == "keep"


def test_recoverable_vendor_error_for_active_response_conflict() -> None:
    assert is_recoverable_vendor_error(
        {
            "type": "error",
            "error": {
                "type": "invalid_request_error",
                "code": "invalid_value",
                "message": "Cannot create response while another response is in progress.",
            },
        }
    )
    assert is_recoverable_vendor_error(
        {
            "type": "error",
            "error": {
                "type": "invalid_request_error",
                "message": "No active response to cancel.",
            },
        }
    )
    assert not is_recoverable_vendor_error(
        {
            "type": "error",
            "error": {
                "type": "server_error",
                "code": "server_error",
                "message": "internal failure",
            },
        }
    )


def test_redact_realtime_event_hides_audio() -> None:
    audio_b64 = base64.b64encode(b"secret-audio").decode("ascii")
    redacted = redact_realtime_event({"type": "response.audio.delta", "delta": audio_b64})
    assert "secret-audio" not in str(redacted)
    assert "omitted" in redacted["delta"]


def test_merge_vision_instructions_for_inject() -> None:
    """vision.inject 依赖的照片块拼接可单测，不打真实 WebSocket。"""
    from coco.modules.voice.prompts import merge_instructions_with_vision

    merged = merge_instructions_with_vision(
        "基线陪伴规则",
        "桌上有一杯茶",
        source="album",
    )
    assert "基线陪伴规则" in merged
    assert "桌上有一杯茶" in merged
    assert "当前照片上下文" in merged
