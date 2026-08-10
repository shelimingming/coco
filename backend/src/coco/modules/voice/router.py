"""语音能力与实时通话 WebSocket 路由。"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, WebSocket
from starlette.websockets import WebSocketState

from coco.config import Settings, get_settings
from coco.database import get_session_factory
from coco.errors import AppError
from coco.modules.voice.schemas import VoiceCapabilitiesResponse
from coco.modules.voice.service import resolve_ws_user, run_realtime_bridge

router = APIRouter(prefix="/v1/voice", tags=["voice"])


@router.get("/capabilities", response_model=VoiceCapabilitiesResponse)
async def get_voice_capabilities(
    settings: Settings = Depends(get_settings),
) -> VoiceCapabilitiesResponse:
    """登录前后均可查询；无 Key 时 realtime=false。"""
    return VoiceCapabilitiesResponse(realtime=settings.realtime_available)


@router.websocket("/realtime")
async def voice_realtime(
    websocket: WebSocket,
    settings: Settings = Depends(get_settings),
) -> None:
    """父母端实时语音陪伴：JWT 经 query access_token 传入。

    鉴权使用短生命周期 DB 会话；通过后只保留 user_id 进入长桥接。
    """
    await websocket.accept()
    factory = get_session_factory()
    user_id: UUID
    async with factory() as session:
        try:
            user = await resolve_ws_user(websocket, settings=settings, session=session)
            user_id = user.id
        except AppError as exc:
            if websocket.client_state == WebSocketState.CONNECTED:
                await websocket.send_json(
                    {"type": "error", "code": exc.code, "message": exc.message}
                )
                await websocket.close(code=1008 if exc.status_code in {401, 403} else 1011)
            return

    await run_realtime_bridge(
        websocket,
        settings=settings,
        user_id=user_id,
        # 识图页「还想问」经 query 传入结论摘要（限长，避免撑爆 URL）
        look_context=_clip_look_context(websocket.query_params.get("look_context")),
    )


def _clip_look_context(raw: str | None) -> str | None:
    text = (raw or "").strip()
    if not text:
        return None
    if len(text) > 400:
        return text[:400]
    return text
