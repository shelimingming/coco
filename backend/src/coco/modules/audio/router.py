"""ASR / TTS 路由：音频只在请求内存中，不落盘。"""

from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, File, Query, Response, UploadFile

from coco.deps import CurrentUserDep, SettingsDep
from coco.errors import AppError
from coco.models.user import UserRole
from coco.modules.audio.schemas import SpeechRequest, TranscriptionResponse
from coco.providers.qwen_asr import QwenAsrClient
from coco.providers.qwen_tts import QwenTtsClient

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/audio", tags=["audio"])

_MAX_AUDIO_BYTES = 10 * 1024 * 1024
_ALLOWED_AUDIO = {
    "audio/aac",
    "audio/flac",
    "audio/m4a",
    "audio/mpeg",
    "audio/mp3",
    "audio/ogg",
    "audio/opus",
    "audio/wav",
    "audio/webm",
    "audio/x-m4a",
    "audio/x-wav",
}


def _require_parent(user: CurrentUserDep) -> None:
    if user.role != UserRole.PARENT.value:
        raise AppError(403, "auth.role_required", "只有老人模式可以使用语音识别。")


def _require_api_key(settings: SettingsDep) -> None:
    key = settings.aliyun_api_key
    if key is None or not key.get_secret_value().strip():
        raise AppError(
            503,
            "audio.unavailable",
            "语音服务暂时不可用。您可以稍后再试，刚才的声音没有保存。",
        )


@router.post("/transcriptions", response_model=TranscriptionResponse)
async def transcribe(
    user: CurrentUserDep,
    settings: SettingsDep,
    audio: Annotated[UploadFile, File(description="整段录音")],
    language: Annotated[str | None, Query()] = "zh",
) -> TranscriptionResponse:
    """父母端 ASR：原始音频仅在本请求内存中。"""
    _require_parent(user)
    _require_api_key(settings)

    content_type = (audio.content_type or "audio/wav").split(";")[0].strip().lower()
    if content_type not in _ALLOWED_AUDIO:
        raise AppError(
            415,
            "audio.unsupported_format",
            "暂时不支持这种录音格式。请再说一次。",
        )
    try:
        data = await audio.read(_MAX_AUDIO_BYTES + 1)
    except Exception as exc:
        raise AppError(
            400,
            "audio.read_failed",
            "录音读取失败。请再说一次，刚才没有保存。",
        ) from exc
    if not data:
        raise AppError(400, "audio.empty", "没有听到声音。请靠近一点再说一次。")
    if len(data) > _MAX_AUDIO_BYTES:
        raise AppError(
            413,
            "audio.too_large",
            "这段话太长了。请说短一点再试，刚才没有保存。",
        )

    assert settings.aliyun_api_key is not None
    try:
        client = QwenAsrClient(
            api_key=settings.aliyun_api_key,
            model=settings.asr_model,
            base_url=settings.aliyun_http_base_url,
        )
        result = await client.transcribe(
            data,
            content_type=content_type,
            language=language,
        )
    except AppError:
        raise
    except Exception:
        logger.warning("asr_failed", exc_info=True)
        raise AppError(
            502,
            "audio.asr_failed",
            "刚才没听清。请再说一次，声音没有保存。",
        ) from None
    return TranscriptionResponse(text=result.text, language=result.language)


@router.post("/speech")
async def synthesize(
    body: SpeechRequest,
    user: CurrentUserDep,
    settings: SettingsDep,
) -> Response:
    """父母端 TTS：返回 MP3，不缓存。"""
    _require_parent(user)
    _require_api_key(settings)
    assert settings.aliyun_api_key is not None
    try:
        client = QwenTtsClient(
            api_key=settings.aliyun_api_key,
            model=settings.tts_model,
            voice=settings.tts_voice,
            base_url=settings.aliyun_http_base_url,
        )
        result = await client.synthesize(
            body.text,
            voice=body.voice,
            speech_rate=body.speech_rate,
        )
    except AppError:
        raise
    except Exception:
        logger.warning("tts_failed", exc_info=True)
        raise AppError(
            502,
            "audio.tts_failed",
            "暂时播不出声音。您可以看屏幕上的字，稍后再试。",
        ) from None
    return Response(
        content=result.audio,
        media_type=result.content_type,
        headers={"Cache-Control": "no-store"},
    )
