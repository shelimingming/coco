"""阿里云百炼 TTS：文字合成语音；音频 URL 仅可信域名，字节不落盘。"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from urllib.parse import urlparse

import httpx
from pydantic import SecretStr

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class SpeechResult:
    audio: bytes
    content_type: str = "audio/mpeg"


class QwenTtsClient:
    def __init__(
        self,
        *,
        api_key: SecretStr,
        model: str,
        voice: str,
        base_url: str,
        timeout_seconds: float = 30.0,
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
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(
                f"{self.base_url}/api/v1/services/audio/tts/SpeechSynthesizer",
                headers={"Authorization": f"Bearer {self._api_key.get_secret_value()}"},
                json={
                    "model": self.model,
                    "input": {
                        "text": cleaned,
                        "voice": voice or self._voice,
                        "format": "mp3",
                        "sample_rate": 24000,
                        "rate": speech_rate,
                    },
                },
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
        return SpeechResult(audio=audio, content_type="audio/mpeg")


def _tts_audio_url(body: object) -> str:
    output = body.get("output") if isinstance(body, dict) else None
    audio = output.get("audio") if isinstance(output, dict) else None
    url = audio.get("url") if isinstance(audio, dict) else None
    if not isinstance(url, str) or not url:
        raise RuntimeError("语音合成未返回地址")
    return url


def _is_trusted_aliyun_audio_url(url: str) -> bool:
    parsed = urlparse(url)
    hostname = parsed.hostname or ""
    return parsed.scheme in {"http", "https"} and hostname.endswith(".aliyuncs.com")
