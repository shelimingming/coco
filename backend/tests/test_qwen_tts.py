"""Qwen TTS 客户端：新 multimodal 路径与音频嗅探。"""

from __future__ import annotations

from coco.providers.qwen_tts import (
    _is_trusted_aliyun_audio_url,
    _sniff_audio_content_type,
    _tts_audio_url,
)


def test_tts_audio_url_from_multimodal_body() -> None:
    url = _tts_audio_url(
        {
            "output": {
                "audio": {
                    "url": "https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/a.wav",
                }
            }
        }
    )
    assert url.endswith(".wav")


def test_trusted_oss_result_host() -> None:
    assert _is_trusted_aliyun_audio_url(
        "http://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/x.wav"
    )
    assert not _is_trusted_aliyun_audio_url("https://evil.example/x.wav")


def test_sniff_wav_and_mp3() -> None:
    assert _sniff_audio_content_type(b"RIFF....WAVE") == "audio/wav"
    assert _sniff_audio_content_type(b"ID3........") == "audio/mpeg"
