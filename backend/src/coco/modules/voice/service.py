"""鉴权 WebSocket：把 Flutter 精简协议桥接到 Qwen-Audio Realtime。

密钥只留在服务端；下行事件脱敏后不含供应商原始音频原文日志。
提醒/分享经 Function Calling；need_confirmation 时推送 action.pending 大卡，
点卡确认走 action.confirm，亦可语音说「好」再以 user_confirmed=true 落库。
记忆开场注入并静默写入；通话过程落库最终转写与（非记忆）工具调用。
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
from uuid import UUID

from fastapi import WebSocket
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.websockets import WebSocketDisconnect, WebSocketState

from coco.config import Settings
from coco.database import get_session_factory
from coco.errors import AppError
from coco.models.auth import AuthSession
from coco.models.conversation import ConversationItemKind, ConversationStatus
from coco.models.family import FamilyStatus
from coco.models.user import User, UserRole, UserStatus
from coco.modules.conversations.service import (
    append_tool_call,
    append_utterance,
    end_conversation,
    start_conversation,
)
from coco.modules.family.service import get_family
from coco.modules.memories.service import MemoryService
from coco.modules.voice.pending_actions import (
    CONFIRMABLE_KINDS,
    PendingActionStore,
    PendingVoiceAction,
    new_draft_id,
)
from coco.modules.voice.prompts import (
    COCO_REALTIME_COMPANION_PROMPT,
    build_companion_instructions,
)
from coco.modules.voice.tools import VOICE_TOOL_DEFINITIONS, dispatch_voice_tool
from coco.providers.qwen_realtime import (
    QwenAudioRealtimeClient,
    RealtimeProviderError,
    RealtimeSessionConfig,
    TurnDetectionMode,
    redact_realtime_event,
)
from coco.security import decode_access_token

logger = logging.getLogger(__name__)

# 写回模型：屏幕已出卡，禁止连环「对吗」
_NEED_CONFIRM_UI_HINT = (
    "屏幕已弹出确认大卡。只需简短说一句：请点一下确认，或者说好。不要连环追问，不要声称已办妥。"
)
_SCREEN_CONFIRMED_PROMPT = (
    "用户已在屏幕上确认该操作，业务已办妥。"
    "请直接简短告知已经设好/已经告诉家人，不要再追问对不对，也不要再次调用创建工具。"
)
_SCREEN_CANCELLED_PROMPT = (
    "用户在屏幕上点了「先不要」，该操作已取消。请简短确认已取消，不要再执行该操作。"
)

RealtimeClientFactory = Callable[..., Awaitable[QwenAudioRealtimeClient] | QwenAudioRealtimeClient]


class _SeqCounter:
    """单次通话内单调序号，避免多条短 session 竞态。"""

    def __init__(self) -> None:
        self._value = 0

    def next(self) -> int:
        self._value += 1
        return self._value


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


async def _active_bound_child_name(session: AsyncSession, user: User) -> str | None:
    """已 active 绑定则返回子女昵称（可能为空串）；未绑定返回 None。"""
    family = await get_family(session, user)
    if family is None or family.child_user_id is None or family.status != FamilyStatus.ACTIVE.value:
        return None
    child = await session.get(User, family.child_user_id)
    return (child.display_name if child else None) or ""


async def _load_companion_instructions(user_id: UUID) -> str:
    """建连前加载姓名、绑定子女与已确认记忆，拼进系统提示。"""
    factory = get_session_factory()
    async with factory() as session:
        user = await session.get(User, user_id)
        if user is None:
            return build_companion_instructions([])
        name = user.display_name
        child_name = await _active_bound_child_name(session, user)
        try:
            memories = await MemoryService().list_for_user(session, user=user)
        except AppError:
            logger.warning("load_memories_for_voice_failed user_id=%s", user_id)
            return build_companion_instructions([], user_name=name, child_name=child_name)
        return build_companion_instructions(
            [m.content for m in memories],
            user_name=name,
            child_name=child_name,
        )


async def create_default_realtime_client(
    settings: Settings,
    *,
    instructions: str | None = None,
) -> QwenAudioRealtimeClient:
    if settings.aliyun_api_key is None:
        raise AppError(503, "realtime.unavailable", "实时语音暂时不可用，请稍后再试。")
    client = QwenAudioRealtimeClient(
        api_key=settings.aliyun_api_key,
        model=settings.realtime_model,
        base_url=settings.realtime_websocket_url,
        session=RealtimeSessionConfig(
            modalities=("text", "audio"),
            voice=settings.realtime_voice,
            instructions=instructions or COCO_REALTIME_COMPANION_PROMPT,
            turn_detection_mode=TurnDetectionMode.SERVER_VAD,
            tools=VOICE_TOOL_DEFINITIONS,
        ),
    )
    await client.connect()
    return client


def _vendor_error_fields(event: dict[str, Any]) -> tuple[str, str, str]:
    """解析百炼 error 事件的 code / type / message（供日志与可恢复判断）。"""
    error = event.get("error")
    code = "realtime.vendor_error"
    err_type = ""
    message = ""
    if isinstance(error, dict):
        code = str(error.get("code") or code)
        err_type = str(error.get("type") or "")
        raw = error.get("message")
        if isinstance(raw, str):
            message = raw
    return code, err_type, message


def is_recoverable_vendor_error(event: dict[str, Any]) -> bool:
    """客户端状态类错误：连接可继续，不应整通挂掉。"""
    code, err_type, message = _vendor_error_fields(event)
    text = f"{code} {err_type} {message}".lower()
    # 上一轮 response 未结束又发 response.create；或无进行中 response 时 cancel
    if "another response is in progress" in text:
        return True
    if "no active response" in text or "no response to cancel" in text:
        return True
    if (
        err_type == "invalid_request_error"
        and "response" in text
        and ("progress" in text or "cancel" in text)
    ):
        return True
    return False


def map_vendor_event(
    event: dict[str, Any], assistant_text: str
) -> tuple[dict[str, Any] | None, str]:
    """把百炼原生事件映射为客户端精简协议；未知事件返回 None。"""
    event_type = event.get("type")
    if event_type == "error":
        code, _, _ = _vendor_error_fields(event)
        message = "语音服务暂时不可用，请稍后再试。"
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
    user_id: UUID,
    client_factory: RealtimeClientFactory | None = None,
) -> None:
    """桥接供应商 Realtime，直到任一侧关闭。

    调用前须已 accept，并完成父母端鉴权；长连接期间用短生命周期 session 执行工具与落库。
    """
    vendor: QwenAudioRealtimeClient | None = None
    conversation_id: UUID | None = None
    end_status = ConversationStatus.CLOSED.value
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

        conversation_id = await start_conversation(user_id)
        seq = _SeqCounter()

        if client_factory is None:
            # 默认路径：注入记忆后再连百炼
            instructions = await _load_companion_instructions(user_id)
            active_vendor = await create_default_realtime_client(
                settings, instructions=instructions
            )
        else:
            maybe_client = client_factory(settings)
            active_vendor = cast(
                QwenAudioRealtimeClient,
                await maybe_client if asyncio.iscoroutine(maybe_client) else maybe_client,
            )
        vendor = active_vendor
        # 通话作用域：提醒/分享待确认草稿（点卡或语音二选一）
        pending_store = PendingActionStore()
        await _send_json(websocket, _client_event("session.ready"))

        recv_task = asyncio.create_task(
            _forward_vendor_events(
                websocket,
                active_vendor,
                settings=settings,
                user_id=user_id,
                conversation_id=conversation_id,
                seq=seq,
                pending_store=pending_store,
            ),
            name="realtime-vendor-forward",
        )
        try:
            await _consume_client_events(
                websocket,
                active_vendor,
                settings=settings,
                user_id=user_id,
                conversation_id=conversation_id,
                seq=seq,
                pending_store=pending_store,
            )
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
        end_status = ConversationStatus.ERROR.value
        await _send_json(
            websocket,
            _client_event("error", code=exc.code, message=exc.message),
        )
        if websocket.client_state == WebSocketState.CONNECTED:
            await websocket.close(code=1008 if exc.status_code in {401, 403} else 1011)
    except RealtimeProviderError as exc:
        end_status = ConversationStatus.ERROR.value
        logger.warning("realtime_vendor_failed code=%s", exc.code)
        await _send_json(
            websocket,
            _client_event(
                "error",
                code=exc.code,
                message="刚才连不上语音服务。您可以稍后再试；若已说过话，可在历史记录里查看。",
            ),
        )
    except WebSocketDisconnect:
        pass
    except Exception:
        end_status = ConversationStatus.ERROR.value
        logger.exception("realtime_bridge_unexpected")
        await _send_json(
            websocket,
            _client_event(
                "error",
                code="realtime.internal_error",
                message="语音通话出了点问题。您可以稍后再试；已说过的内容会尽量保存在历史记录里。",
            ),
        )
    finally:
        if conversation_id is not None:
            await end_conversation(conversation_id, status=end_status)
        if vendor is not None:
            with contextlib.suppress(Exception):
                await vendor.close()
        await _send_json(websocket, _client_event("closed"))
        if websocket.client_state == WebSocketState.CONNECTED:
            await websocket.close()


async def _resolve_child_display_name(user_id: UUID) -> str:
    """分享卡「给谁」：绑定子女昵称，没有则用「家人」。"""
    factory = get_session_factory()
    async with factory() as session:
        user = await session.get(User, user_id)
        if user is None:
            return "家人"
        name = await _active_bound_child_name(session, user)
        if name is None:
            return "家人"
        return name.strip() or "家人"


def _build_pending_display(
    kind: str,
    arguments: dict[str, Any],
    tool_result: dict[str, Any],
    *,
    share_to: str = "家人",
) -> dict[str, Any]:
    if kind == "create_reminder":
        schedule_type = str(
            arguments.get("schedule_type") or tool_result.get("schedule_type") or "ONCE"
        )
        schedule_time = str(
            tool_result.get("schedule_time") or arguments.get("schedule_time") or ""
        )
        # 工具结果可能是 HH:MM，参数也可能是
        if len(schedule_time) >= 5 and schedule_time[2] == ":":
            schedule_time = schedule_time[:5]
        title = str(arguments.get("title") or tool_result.get("title") or "").strip()
        return {
            "title": title,
            "schedule_type": schedule_type,
            "schedule_time": schedule_time,
            "repeat_label": "每天" if schedule_type == "DAILY" else "仅一次",
        }
    if kind == "share_to_child":
        return {
            "summary": str(arguments.get("summary") or tool_result.get("summary") or "").strip(),
            "urgency": str(arguments.get("urgency") or tool_result.get("urgency") or "LOW"),
            "share_to": share_to,
        }
    return {}


def _enrich_need_confirmation_output(raw_output: str) -> str:
    try:
        parsed = json.loads(raw_output)
    except json.JSONDecodeError:
        return raw_output
    if not isinstance(parsed, dict) or parsed.get("status") != "need_confirmation":
        return raw_output
    parsed["ui"] = "confirmation_card_shown"
    parsed["hint"] = _NEED_CONFIRM_UI_HINT
    return json.dumps(parsed, ensure_ascii=False)


async def _consume_client_events(
    websocket: WebSocket,
    vendor: QwenAudioRealtimeClient,
    *,
    settings: Settings,
    user_id: UUID,
    conversation_id: UUID | None,
    seq: _SeqCounter,
    pending_store: PendingActionStore,
) -> None:
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
        if event_type == "action.confirm":
            draft_id = event.get("draft_id")
            if isinstance(draft_id, str) and draft_id:
                await _confirm_pending_from_screen(
                    websocket,
                    vendor,
                    draft_id=draft_id,
                    settings=settings,
                    user_id=user_id,
                    conversation_id=conversation_id,
                    seq=seq,
                    pending_store=pending_store,
                )
            continue
        if event_type == "action.cancel":
            draft_id = event.get("draft_id")
            if isinstance(draft_id, str) and draft_id:
                await _cancel_pending_from_screen(
                    websocket,
                    vendor,
                    draft_id=draft_id,
                    pending_store=pending_store,
                )
            continue
        if event_type == "vision.inject":
            await _inject_vision_from_client(websocket, vendor, event)
            continue
        # 忽略未知上行事件，避免供应商协议泄漏到客户端约定。


async def _inject_vision_from_client(
    websocket: WebSocket,
    vendor: QwenAudioRealtimeClient,
    event: dict[str, Any],
) -> None:
    """把多模态读图结果写入 Realtime instructions 并触发可可开口。"""
    scene = event.get("scene_description")
    if not isinstance(scene, str) or not scene.strip():
        await _send_json(
            websocket,
            _client_event(
                "error",
                code="realtime.vision_empty",
                message="照片内容没传过来。请再选一张照片试试。",
            ),
        )
        return
    source = event.get("source")
    source_str = source.strip() if isinstance(source, str) else None
    # 打断当前播报，再注入新图上下文
    with contextlib.suppress(Exception):
        await vendor.cancel_response()
    try:
        await vendor.inject_vision_context_and_respond(
            scene_description=scene.strip(),
            source=source_str,
        )
    except Exception:
        logger.exception("realtime_vision_inject_failed")
        await _send_json(
            websocket,
            _client_event(
                "error",
                code="realtime.vision_inject_failed",
                message="照片看完了，但没接上语音。您可以再点「说话」继续聊。",
            ),
        )
        return
    await _send_json(
        websocket,
        _client_event(
            "vision.injected",
            source=source_str,
        ),
    )


async def _confirm_pending_from_screen(
    websocket: WebSocket,
    vendor: QwenAudioRealtimeClient,
    *,
    draft_id: str,
    settings: Settings,
    user_id: UUID,
    conversation_id: UUID | None,
    seq: _SeqCounter,
    pending_store: PendingActionStore,
) -> None:
    """大卡点确认：落库后注入模型，避免再口头追问。"""
    pending = await pending_store.take_matching(draft_id)
    if pending is None:
        # 语音侧可能已确认：幂等收卡，不重复写
        await _send_json(
            websocket,
            _client_event(
                "action.resolved",
                draft_id=draft_id,
                status="already_resolved",
            ),
        )
        return

    confirmed_args = {**pending.arguments, "user_confirmed": True}
    factory = get_session_factory()
    async with factory() as session:
        fresh_user = await session.get(User, user_id)
        if fresh_user is None:
            await _send_json(
                websocket,
                _client_event(
                    "error",
                    code="auth.invalid_token",
                    message="登录状态无效，请重新登录。刚才没有完成确认。",
                ),
            )
            return
        output = await dispatch_voice_tool(
            session=session,
            settings=settings,
            user=fresh_user,
            name=pending.kind,
            arguments=confirmed_args,
        )

    try:
        result = json.loads(output)
    except json.JSONDecodeError:
        result = {"status": "error", "message": "刚才没办成，请再说一次。"}

    if conversation_id is not None:
        await append_tool_call(
            conversation_id,
            seq=seq.next(),
            tool_name=pending.kind,
            arguments=confirmed_args,
            result_output=output,
        )

    if isinstance(result, dict) and result.get("status") == "error":
        # 失败不拆通话：恢复草稿并重新出卡，由模型口头说明原因
        await pending_store.replace(pending)
        await _send_json(
            websocket,
            _client_event("action.pending", **pending.to_client_payload()),
        )
        fail_msg = str(result.get("message") or "刚才没办成，请再说一次。")
        with contextlib.suppress(Exception):
            await vendor.cancel_response()
        with contextlib.suppress(Exception):
            await vendor.inject_user_text_and_respond(
                f"用户点了屏幕确认，但业务失败：{fail_msg}请简短说明原因，可请用户再试或改说法。"
            )
        return

    await _send_json(
        websocket,
        _client_event(
            "action.resolved",
            draft_id=draft_id,
            kind=pending.kind,
            status="confirmed",
        ),
    )
    with contextlib.suppress(Exception):
        await vendor.cancel_response()
    with contextlib.suppress(Exception):
        await vendor.inject_user_text_and_respond(_SCREEN_CONFIRMED_PROMPT)


async def _cancel_pending_from_screen(
    websocket: WebSocket,
    vendor: QwenAudioRealtimeClient,
    *,
    draft_id: str,
    pending_store: PendingActionStore,
) -> None:
    pending = await pending_store.take_matching(draft_id)
    await _send_json(
        websocket,
        _client_event(
            "action.resolved",
            draft_id=draft_id,
            kind=pending.kind if pending else None,
            status="cancelled",
        ),
    )
    if pending is None:
        return
    with contextlib.suppress(Exception):
        await vendor.cancel_response()
    with contextlib.suppress(Exception):
        await vendor.inject_user_text_and_respond(_SCREEN_CANCELLED_PROMPT)


async def _handle_function_call(
    websocket: WebSocket,
    vendor: QwenAudioRealtimeClient,
    event: dict[str, Any],
    *,
    settings: Settings,
    user_id: UUID,
    conversation_id: UUID | None,
    seq: _SeqCounter,
    pending_store: PendingActionStore,
) -> None:
    call_id = event.get("call_id")
    name = event.get("name")
    raw_args = event.get("arguments")
    if not isinstance(call_id, str) or not isinstance(name, str):
        return
    arguments: dict[str, Any] = {}
    if isinstance(raw_args, str) and raw_args.strip():
        try:
            parsed = json.loads(raw_args)
            if isinstance(parsed, dict):
                arguments = parsed
        except json.JSONDecodeError:
            arguments = {}
    elif isinstance(raw_args, dict):
        arguments = raw_args

    # 长连接不长期占库连接：每次工具调用新开短生命周期 session
    factory = get_session_factory()
    async with factory() as session:
        fresh_user = await session.get(User, user_id)
        if fresh_user is None:
            output = json.dumps(
                {"status": "error", "message": "登录状态无效，请重新登录。"},
                ensure_ascii=False,
            )
        else:
            output = await dispatch_voice_tool(
                session=session,
                settings=settings,
                user=fresh_user,
                name=name,
                arguments=arguments,
            )

    # need_confirmation → 推大卡；语音确认成功 → 收卡（防双通道重复）
    if name in CONFIRMABLE_KINDS:
        output = await _sync_pending_after_tool(
            websocket,
            name=name,
            arguments=arguments,
            output=output,
            user_id=user_id,
            pending_store=pending_store,
        )

    # 记忆静默写入：不进通话历史，父母只在「可可记得的我」里看
    if conversation_id is not None and name != "save_memory":
        await append_tool_call(
            conversation_id,
            seq=seq.next(),
            tool_name=name,
            arguments=arguments,
            result_output=output,
        )
    # 只写回结果；response.create 须等本轮 response.done，否则百炼会报 in progress
    await vendor.send_tool_output(call_id=call_id, output=output)


async def _sync_pending_after_tool(
    websocket: WebSocket,
    *,
    name: str,
    arguments: dict[str, Any],
    output: str,
    user_id: UUID,
    pending_store: PendingActionStore,
) -> str:
    try:
        result = json.loads(output)
    except json.JSONDecodeError:
        return output
    if not isinstance(result, dict):
        return output

    status = result.get("status")
    if status == "need_confirmation":
        share_to = "家人"
        if name == "share_to_child":
            share_to = await _resolve_child_display_name(user_id)
        display = _build_pending_display(name, arguments, result, share_to=share_to)
        # 存确认时用的参数快照（不含 user_confirmed，确认时再置 true）
        snap = {k: v for k, v in arguments.items() if k != "user_confirmed"}
        action = PendingVoiceAction(
            draft_id=new_draft_id(),
            kind=name,
            arguments=snap,
            display=display,
        )
        await pending_store.replace(action)
        await _send_json(
            websocket,
            _client_event("action.pending", **action.to_client_payload()),
        )
        return _enrich_need_confirmation_output(output)

    if status == "error":
        return output

    # 落库成功（含语音说「好」后的 true 调用）：收起大卡
    if result.get("id") is not None:
        cleared = await pending_store.clear_if_kind(name)
        await _send_json(
            websocket,
            _client_event(
                "action.resolved",
                draft_id=cleared.draft_id if cleared else None,
                kind=name,
                status="confirmed",
            ),
        )
    return output


async def _forward_vendor_events(
    websocket: WebSocket,
    vendor: QwenAudioRealtimeClient,
    *,
    settings: Settings,
    user_id: UUID,
    conversation_id: UUID | None,
    seq: _SeqCounter,
    pending_store: PendingActionStore,
) -> None:
    assistant_text = ""
    final_sent = False
    # 工具已写回、等待本轮 response.done 后再 create 二轮（避免 in-progress 冲突）
    needs_tool_followup = False
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

            # Function Calling：执行业务；need_confirmation 时另推 action.pending
            if event_type == "response.function_call_arguments.done":
                try:
                    await _handle_function_call(
                        websocket,
                        vendor,
                        event,
                        settings=settings,
                        user_id=user_id,
                        conversation_id=conversation_id,
                        seq=seq,
                        pending_store=pending_store,
                    )
                    needs_tool_followup = True
                except Exception:
                    logger.exception("realtime_function_call_failed")
                    call_id = event.get("call_id")
                    if isinstance(call_id, str):
                        with contextlib.suppress(Exception):
                            await vendor.send_tool_output(
                                call_id=call_id,
                                output=json.dumps(
                                    {
                                        "status": "error",
                                        "message": "刚才没办成，请再说一次。",
                                    },
                                    ensure_ascii=False,
                                ),
                            )
                            needs_tool_followup = True
                continue

            # 本轮结束：若刚写回过工具结果，再触发基于结果的口语回复
            if event_type == "response.done" and needs_tool_followup:
                needs_tool_followup = False
                mapped_done, assistant_text = map_vendor_event(event, assistant_text)
                if mapped_done is not None and mapped_done.get("type") == "assistant.final":
                    if not final_sent:
                        final_sent = True
                        text = str(mapped_done.get("text") or "").strip()
                        if conversation_id is not None and text:
                            await append_utterance(
                                conversation_id,
                                seq=seq.next(),
                                kind=ConversationItemKind.ASSISTANT.value,
                                text=text,
                            )
                        await _send_json(websocket, mapped_done)
                    assistant_text = ""
                with contextlib.suppress(Exception):
                    await vendor.create_response()
                continue

            if event_type == "error":
                code, err_type, vendor_msg = _vendor_error_fields(event)
                logger.warning(
                    "realtime_vendor_error code=%s type=%s message=%s",
                    code,
                    err_type,
                    vendor_msg[:300],
                )
                # 状态类错误保持通话；致命错误才下发给父母端错误卡
                if is_recoverable_vendor_error(event):
                    continue

            mapped, assistant_text = map_vendor_event(event, assistant_text)
            if mapped is None:
                continue
            if mapped.get("type") == "assistant.final":
                if final_sent:
                    continue
                final_sent = True
                text = str(mapped.get("text") or "").strip()
                if conversation_id is not None and text:
                    await append_utterance(
                        conversation_id,
                        seq=seq.next(),
                        kind=ConversationItemKind.ASSISTANT.value,
                        text=text,
                    )
                assistant_text = ""
            elif mapped.get("type") == "user.final":
                text = str(mapped.get("text") or "").strip()
                if conversation_id is not None and text:
                    await append_utterance(
                        conversation_id,
                        seq=seq.next(),
                        kind=ConversationItemKind.USER.value,
                        text=text,
                    )
            await _send_json(websocket, mapped)
    except RealtimeProviderError as exc:
        await _send_json(
            websocket,
            _client_event(
                "error",
                code=exc.code,
                message="语音服务中断了。您可以重新点形象开始；已说过的内容会尽量保存在历史记录里。",
            ),
        )
    except WebSocketDisconnect:
        return
