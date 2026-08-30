"""ASR / TTS 请求响应。"""

from __future__ import annotations

from pydantic import BaseModel, Field


class TranscriptionResponse(BaseModel):
    text: str
    language: str | None = None


class SpeechRequest(BaseModel):
    # qwen3-tts-flash 约 600 字；小记全文朗读需要更长于开场白
    text: str = Field(..., min_length=1, max_length=600)
    voice: str | None = None
    speech_rate: float = Field(default=0.9, ge=0.5, le=2.0)
