"""阿里云百炼 ASR：整段音频转文字；音频仅在请求内存中，不落盘。"""

from __future__ import annotations

import base64
import logging
from dataclasses import dataclass
from typing import Any

import httpx
from pydantic import SecretStr

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class TranscriptionResult:
    text: str
    language: str | None = None


class QwenAsrClient:
    def __init__(
        self,
        *,
        api_key: SecretStr,
        model: str,
        base_url: str,
        timeout_seconds: float = 30.0,
    ) -> None:
        self._api_key = api_key
        self.model = model
        self.base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds

    async def transcribe(
        self,
        audio: bytes,
        *,
        content_type: str,
        language: str | None = None,
    ) -> TranscriptionResult:
        data_uri = f"data:{content_type};base64,{base64.b64encode(audio).decode('ascii')}"
        parameters: dict[str, Any] = {
            "format": _audio_format(content_type),
            "sample_rate": "16000",
        }
        if language:
            parameters["language_hints"] = [language]
        payload = {
            "model": self.model,
            "input": {
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "input_audio",
                                "input_audio": {"data": data_uri},
                            }
                        ],
                    }
                ]
            },
            "parameters": parameters,
        }
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(
                f"{self.base_url}/api/v1/services/aigc/multimodal-generation/generation",
                headers={
                    "Authorization": f"Bearer {self._api_key.get_secret_value()}",
                    "X-DashScope-SSE": "disable",
                },
                json=payload,
            )
            response.raise_for_status()
            body = response.json()

        output = body.get("output") if isinstance(body, dict) else None
        text = output.get("text") if isinstance(output, dict) else None
        if not isinstance(text, str) or not text.strip():
            raise RuntimeError("语音识别结果为空")
        return TranscriptionResult(text=text.strip(), language=language)


def _audio_format(content_type: str) -> str:
    return {
        "audio/aac": "aac",
        "audio/flac": "flac",
        "audio/m4a": "m4a",
        "audio/mpeg": "mp3",
        "audio/mp3": "mp3",
        "audio/ogg": "ogg",
        "audio/opus": "opus",
        "audio/wav": "wav",
        "audio/webm": "webm",
        "audio/x-m4a": "m4a",
        "audio/x-wav": "wav",
    }.get(content_type, "wav")
