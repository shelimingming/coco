"""阿里云百炼 TTS（Qwen3-TTS）：文字合成语音；音频 URL 仅可信域名，字节不落盘。"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from urllib.parse import urlparse

import httpx
from pydantic import SecretStr

logger = logging.getLogger(__name__)

# 非实时 Qwen-TTS 走 multimodal-generation，勿再用旧 SpeechSynthesizer 路径
_TTS_PATH = "/api/v1/services/aigc/multimodal-generation/generation"


@dataclass(slots=True)
class SpeechResult:
    audio: bytes
    content_type: str = "audio/wav"


class QwenTtsClient:
    def __init__(
        self,
        *,
        api_key: SecretStr,
        model: str,
        voice: str,
        base_url: str,
        timeout_seconds: float = 60.0,
    ) -> None:
        self._api_key = api_key
        self.model = model
        self._voice = voice
        self.base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds

    async def synthesize(
        self,
        text: str,
        *,
        voice: str | None = None,
        speech_rate: float = 0.9,
    ) -> SpeechResult:
        cleaned = text.strip()
        if not cleaned:
            raise RuntimeError("没有可朗读的文字")
        # qwen3-tts-flash 上限约 600 字；超长截断，避免整段 400
        if len(cleaned) > 600:
            cleaned = cleaned[:600]
            logger.info("tts_text_truncated len=600")

        payload: dict[str, object] = {
            "model": self.model,
            "input": {
                "text": cleaned,
                "voice": voice or self._voice,
                "language_type": "Chinese",
            },
        }
        # 旧 Cosy 接口的 rate 在新模型上无效；略偏慢时用 instruct 再说，MVP 先忽略
        _ = speech_rate

        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(
                f"{self.base_url}{_TTS_PATH}",
                headers={"Authorization": f"Bearer {self._api_key.get_secret_value()}"},
                json=payload,
            )
            if response.status_code >= 400:
                logger.warning(
                    "tts_upstream_error status=%s body=%s",
                    response.status_code,
                    response.text[:400],
                )
            response.raise_for_status()
            body = response.json()
            audio_url = _tts_audio_url(body)
            if not _is_trusted_aliyun_audio_url(audio_url):
                raise RuntimeError("语音地址不可信")
            audio_response = await client.get(audio_url)
            audio_response.raise_for_status()
            audio = audio_response.content
        if not audio:
            raise RuntimeError("语音合成结果为空")
        content_type = _sniff_audio_content_type(audio)
        return SpeechResult(audio=audio, content_type=content_type)


def _tts_audio_url(body: object) -> str:
    output = body.get("output") if isinstance(body, dict) else None
    audio = output.get("audio") if isinstance(output, dict) else None
    url = audio.get("url") if isinstance(audio, dict) else None
    if not isinstance(url, str) or not url:
        raise RuntimeError("语音合成未返回地址")
    return url


def _is_trusted_aliyun_audio_url(url: str) -> bool:
    parsed = urlparse(url)
    hostname = (parsed.hostname or "").lower()
    return parsed.scheme in {"http", "https"} and (
        hostname.endswith(".aliyuncs.com") or hostname.endswith(".aliyun.com")
    )


def _sniff_audio_content_type(data: bytes) -> str:
    if data.startswith(b"RIFF"):
        return "audio/wav"
    if data.startswith(b"ID3") or data[:2] == b"\xff\xfb" or data[:2] == b"\xff\xf3":
        return "audio/mpeg"
    return "audio/wav"
