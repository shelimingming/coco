"""鉴权 WebSocket：把 Flutter 精简协议桥接到 Qwen-Audio Realtime。

密钥只留在服务端；下行事件脱敏后不含供应商原始音频原文日志。
实时通话本阶段只做陪伴，不执行提醒/记忆工具。
"""

from __future__ import annotations

import asyncio
import base64
import contextlib
import json
import logging
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime
from typing import Any, cast

from fastapi import WebSocket
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.websockets import WebSocketDisconnect, WebSocketState

from coco.config import Settings
from coco.errors import AppError
from coco.models.auth import AuthSession
from coco.models.user import User, UserRole, UserStatus
from coco.modules.voice.prompts import COCO_REALTIME_COMPANION_PROMPT
from coco.providers.qwen_realtime import (
    QwenAudioRealtimeClient,
    RealtimeProviderError,
    RealtimeSessionConfig,
    TurnDetectionMode,
    redact_realtime_event,
)
from coco.security import decode_access_token

logger = logging.getLogger(__name__)

RealtimeClientFactory = Callable[..., Awaitable[QwenAudioRealtimeClient] | QwenAudioRealtimeClient]


def _client_event(type_: str, **payload: Any) -> dict[str, Any]:
    body: dict[str, Any] = {"type": type_}
    body.update(payload)
    return body


async def _send_json(websocket: WebSocket, event: dict[str, Any]) -> None:
    if websocket.client_state != WebSocketState.CONNECTED:
        return
    await websocket.send_json(event)


async def resolve_ws_user(
    websocket: WebSocket,
    *,
    settings: Settings,
    session: AsyncSession,
) -> User:
    """从 query access_token 或 Authorization Bearer 解析并校验父母端用户。"""
    token = websocket.query_params.get("access_token")
    if not token:
        auth = websocket.headers.get("authorization") or websocket.headers.get("Authorization")
        if auth and auth.lower().startswith("bearer "):
            token = auth[7:].strip()
    if not token:
        raise AppError(401, "auth.missing_token", "请先登录。")

    principal = decode_access_token(settings, token)
    result = await session.execute(
        select(User, AuthSession)
        .join(AuthSession, AuthSession.user_id == User.id)
        .where(
            User.id == principal.user_id,
            AuthSession.id == principal.session_id,
        )
    )
    row = result.one_or_none()
    if row is None:
        raise AppError(401, "auth.invalid_token", "登录状态无效，请重新登录。")

    user, auth_session = row
    if auth_session.revoked_at is not None:
        raise AppError(401, "auth.session_expired", "登录已失效，请重新登录。")

    expires = auth_session.expires_at
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=UTC)
    if expires <= datetime.now(UTC):
        raise AppError(401, "auth.session_expired", "登录已过期，请重新登录。")
    if user.status != UserStatus.ACTIVE.value:
        raise AppError(403, "auth.user_disabled", "账号不可用，请联系支持。")
    # 服务端鉴权是最终判断：只有父母角色可进入实时陪伴
    if user.role != UserRole.PARENT.value:
        raise AppError(403, "auth.role_required", "只有老人模式可以语音陪伴。")
    return user


async def create_default_realtime_client(settings: Settings) -> QwenAudioRealtimeClient:
    if settings.aliyun_api_key is None:
        raise AppError(503, "realtime.unavailable", "实时语音暂时不可用，请稍后再试。")
    client = QwenAudioRealtimeClient(
        api_key=settings.aliyun_api_key,
        model=settings.realtime_model,
        base_url=settings.realtime_websocket_url,
        session=RealtimeSessionConfig(
            modalities=("text", "audio"),
            voice=settings.realtime_voice,
            instructions=COCO_REALTIME_COMPANION_PROMPT,
            turn_detection_mode=TurnDetectionMode.SERVER_VAD,
        ),
    )
    await client.connect()
    return client


def map_vendor_event(
    event: dict[str, Any], assistant_text: str
) -> tuple[dict[str, Any] | None, str]:
    """把百炼原生事件映射为客户端精简协议；未知事件返回 None。"""
    event_type = event.get("type")
    if event_type == "error":
        error = event.get("error")
        message = "语音服务暂时不可用，请稍后再试。"
        code = "realtime.vendor_error"
        if isinstance(error, dict):
            code = str(error.get("code") or code)
        return _client_event("error", code=code, message=message), assistant_text

    if event_type == "input_audio_buffer.speech_started":
        return _client_event("speech.started"), assistant_text

    if event_type == "input_audio_buffer.speech_stopped":
        return _client_event("speech.stopped"), assistant_text

    if event_type == "conversation.item.input_audio_transcription.delta":
        delta = event.get("delta")
        if isinstance(delta, str) and delta:
            return _client_event("user.partial", text=delta), assistant_text
        return None, assistant_text

    if event_type == "conversation.item.input_audio_transcription.completed":
        transcript = event.get("transcript")
        if isinstance(transcript, str) and transcript.strip():
            return _client_event("user.final", text=transcript.strip()), assistant_text
        return None, assistant_text

    if event_type == "response.audio_transcript.delta":
        delta = event.get("delta")
        if isinstance(delta, str) and delta:
            next_text = assistant_text + delta
            return _client_event("assistant.partial", text=delta), next_text
        return None, assistant_text

    if event_type == "response.text.delta":
        delta = event.get("delta")
        if isinstance(delta, str) and delta:
            next_text = assistant_text + delta
            return _client_event("assistant.partial", text=delta), next_text
        return None, assistant_text

    if event_type == "response.audio.delta":
        delta = event.get("delta")
        if isinstance(delta, str) and delta:
            return (
                _client_event("assistant.audio", audio=delta, sample_rate=24000),
                assistant_text,
            )
        return None, assistant_text

    if event_type in {"response.audio_transcript.done", "response.text.done"}:
        text = event.get("transcript") or event.get("text") or assistant_text
        if isinstance(text, str) and text.strip():
            cleaned = text.strip()
            return _client_event("assistant.final", text=cleaned), cleaned
        return None, assistant_text

    if event_type == "response.done":
        text = assistant_text.strip()
        if text:
            return _client_event("assistant.final", text=text), text
        return None, assistant_text

    return None, assistant_text


async def run_realtime_bridge(
    websocket: WebSocket,
    *,
    settings: Settings,
    client_factory: RealtimeClientFactory | None = None,
) -> None:
    """桥接供应商 Realtime，直到任一侧关闭。

    调用前须已 accept，并完成父母端鉴权；本函数不再占用数据库会话。
    """
    vendor: QwenAudioRealtimeClient | None = None
    try:
        if not settings.realtime_available and client_factory is None:
            await _send_json(
                websocket,
                _client_event(
                    "error",
                    code="realtime.unavailable",
                    message="实时语音暂时不可用。您可以稍后再试，刚才没有录下任何声音。",
                ),
            )
            await websocket.close(code=1013)
            return

        factory = client_factory or create_default_realtime_client
        maybe_client = factory(settings)
        active_vendor = cast(
            QwenAudioRealtimeClient,
            await maybe_client if asyncio.iscoroutine(maybe_client) else maybe_client,
        )
        vendor = active_vendor
        await _send_json(websocket, _client_event("session.ready"))

        recv_task = asyncio.create_task(
            _forward_vendor_events(websocket, active_vendor),
            name="realtime-vendor-forward",
        )
        try:
            await _consume_client_events(websocket, active_vendor)
        finally:
            # 先关闭供应商连接以结束 events()，再等待下行转发收尾。
            with contextlib.suppress(Exception):
                await active_vendor.close()
            vendor = None
            if not recv_task.done():
                try:
                    await asyncio.wait_for(recv_task, timeout=2.0)
                except (TimeoutError, asyncio.CancelledError):
                    recv_task.cancel()
                    with contextlib.suppress(asyncio.CancelledError):
                        await recv_task
    except AppError as exc:
        await _send_json(
            websocket,
            _client_event("error", code=exc.code, message=exc.message),
        )
        if websocket.client_state == WebSocketState.CONNECTED:
            await websocket.close(code=1008 if exc.status_code in {401, 403} else 1011)
    except RealtimeProviderError as exc:
        logger.warning("realtime_vendor_failed code=%s", exc.code)
        await _send_json(
            websocket,
            _client_event(
                "error",
                code=exc.code,
                message="刚才连不上语音服务。您可以稍后再试，刚才没有录下任何声音。",
            ),
        )
    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("realtime_bridge_unexpected")
        await _send_json(
            websocket,
            _client_event(
                "error",
                code="realtime.internal_error",
                message="语音通话出了点问题。您可以稍后再试，刚才的内容没有额外保存。",
            ),
        )
    finally:
        if vendor is not None:
            with contextlib.suppress(Exception):
                await vendor.close()
        await _send_json(websocket, _client_event("closed"))
        if websocket.client_state == WebSocketState.CONNECTED:
            await websocket.close()


async def _consume_client_events(websocket: WebSocket, vendor: QwenAudioRealtimeClient) -> None:
    while True:
        raw = await websocket.receive_text()
        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            await _send_json(
                websocket,
                _client_event(
                    "error",
                    code="realtime.invalid_event",
                    message="语音数据格式不正确，请再说一次。",
                ),
            )
            continue
        if not isinstance(event, dict):
            continue
        event_type = event.get("type")
        if event_type == "session.end":
            return
        if event_type == "response.cancel":
            await vendor.cancel_response()
            continue
        if event_type == "audio.commit":
            await vendor.commit_audio_buffer()
            continue
        if event_type == "audio.append":
            audio = event.get("audio")
            if not isinstance(audio, str) or not audio:
                continue
            try:
                pcm = base64.b64decode(audio, validate=False)
            except Exception:
                continue
            if pcm:
                await vendor.append_audio(pcm)
            continue
        # 忽略未知上行事件，避免供应商协议泄漏到客户端约定。


async def _forward_vendor_events(websocket: WebSocket, vendor: QwenAudioRealtimeClient) -> None:
    assistant_text = ""
    final_sent = False
    try:
        async for event in vendor.events():
            logger.debug(
                "realtime_vendor_event %s",
                json.dumps(redact_realtime_event(event), ensure_ascii=False),
            )
            event_type = event.get("type")
            if event_type == "response.created":
                assistant_text = ""
                final_sent = False
            mapped, assistant_text = map_vendor_event(event, assistant_text)
            if mapped is None:
                continue
            if mapped.get("type") == "assistant.final":
                if final_sent:
                    continue
                final_sent = True
                assistant_text = ""
            await _send_json(websocket, mapped)
    except RealtimeProviderError as exc:
        await _send_json(
            websocket,
            _client_event(
                "error",
                code=exc.code,
                message="语音服务中断了。您可以重新点形象开始。刚才的内容没有额外保存。",
            ),
        )
    except WebSocketDisconnect:
        return
