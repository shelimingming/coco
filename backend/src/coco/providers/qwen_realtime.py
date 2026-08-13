"""阿里云百炼 Qwen-Audio Realtime（qwen-audio-3.0-realtime-plus）WebSocket 客户端。

密钥只从调用方传入；音频与转写原文不写入普通日志。
"""

from __future__ import annotations

import asyncio
import base64
import json
import ssl
import time
from collections.abc import AsyncIterator, Mapping, Sequence
from dataclasses import dataclass
from enum import StrEnum
from typing import Any, Literal

import certifi
import websockets
from pydantic import SecretStr
from websockets.asyncio.client import ClientConnection


class RealtimeProviderError(RuntimeError):
    """Realtime 握手或会话交互失败。"""

    def __init__(self, message: str, *, code: str = "realtime_error") -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class TurnDetectionMode(StrEnum):
    """轮次检测模式；会话建立后切换通常需要重连。"""

    SERVER_VAD = "server_vad"
    SMART_TURN = "smart_turn"
    # push-to-talk：客户端提交音频后手动 response.create
    MANUAL = "manual"


@dataclass(slots=True)
class RealtimeSessionConfig:
    modalities: Sequence[Literal["text", "audio"]] = ("text", "audio")
    voice: str = "longanqian"
    instructions: str = ""
    input_audio_format: str = "pcm"
    output_audio_format: str = "pcm"
    turn_detection_mode: TurnDetectionMode = TurnDetectionMode.SERVER_VAD
    # server_vad 参数；仅在 SERVER_VAD 模式下发送
    vad_threshold: float = 0.5
    silence_duration_ms: int = 800
    # Function Calling 工具定义；空列表表示不启用工具
    tools: Sequence[Mapping[str, Any]] = ()


class QwenAudioRealtimeClient:
    """Qwen-Audio Realtime 事件驱动客户端。"""

    def __init__(
        self,
        *,
        api_key: SecretStr,
        model: str,
        base_url: str,
        session: RealtimeSessionConfig | None = None,
        open_timeout_seconds: float = 15.0,
    ) -> None:
        self._api_key = api_key
        self.model = model
        self.base_url = base_url.rstrip("?")
        self.session = session or RealtimeSessionConfig()
        self._open_timeout_seconds = open_timeout_seconds
        self._ws: ClientConnection | None = None
        self._event_seq = 0
        # 建连时的陪伴基线；识图注入只在之上替换照片块，不丢记忆/规则
        self._base_instructions = self.session.instructions

    @property
    def connected(self) -> bool:
        return self._ws is not None

    async def __aenter__(self) -> QwenAudioRealtimeClient:
        await self.connect()
        return self

    async def __aexit__(self, *_exc: object) -> None:
        await self.close()

    async def connect(self) -> None:
        if self._ws is not None:
            return
        url = f"{self.base_url}?model={self.model}"
        headers = {
            "Authorization": f"Bearer {self._api_key.get_secret_value()}",
            # demo / 开发联调默认关闭内容安全巡检回传；正式环境按合规要求调整。
            "x-dashscope-dataInspection": "disable",
        }
        try:
            self._ws = await websockets.connect(
                url,
                additional_headers=headers,
                open_timeout=self._open_timeout_seconds,
                max_size=8 * 1024 * 1024,
                # macOS 官方 Python 常缺系统 CA；显式使用 certifi 避免握手失败。
                ssl=ssl.create_default_context(cafile=certifi.where()),
            )
            # 先消费 session.created，再更新会话，避免首包未读就发配置。
            created = await self.recv_event(timeout_seconds=self._open_timeout_seconds)
            if created.get("type") != "session.created":
                raise RealtimeProviderError(
                    f"期望 session.created，实际收到 {created.get('type')!r}",
                    code="unexpected_handshake_event",
                )
            await self.update_session(self.session)
            updated = await self.recv_event(timeout_seconds=self._open_timeout_seconds)
            if updated.get("type") == "error":
                raise RealtimeProviderError(
                    _error_message(updated),
                    code="session_update_error",
                )
            if updated.get("type") != "session.updated":
                raise RealtimeProviderError(
                    f"期望 session.updated，实际收到 {updated.get('type')!r}",
                    code="unexpected_session_event",
                )
        except RealtimeProviderError:
            await self.close()
            raise
        except websockets.exceptions.InvalidStatus as exc:
            await self.close()
            raise RealtimeProviderError(
                f"WebSocket 握手失败：HTTP {exc.response.status_code}",
                code="websocket_handshake_failed",
            ) from None
        except websockets.exceptions.ConnectionClosedError as exc:
            await self.close()
            raise RealtimeProviderError(
                _close_reason(exc),
                code="model_or_connection_denied",
            ) from None
        except Exception:
            await self.close()
            raise

    async def close(self) -> None:
        if self._ws is None:
            return
        await self._ws.close()
        self._ws = None

    async def recv_event(self, *, timeout_seconds: float | None = None) -> dict[str, Any]:
        ws = self._require_ws()
        try:
            if timeout_seconds is None:
                message = await ws.recv()
            else:
                message = await asyncio.wait_for(ws.recv(), timeout=timeout_seconds)
        except TimeoutError as exc:
            raise RealtimeProviderError("等待服务端事件超时", code="recv_timeout") from exc
        except websockets.exceptions.ConnectionClosedError as exc:
            raise RealtimeProviderError(
                _close_reason(exc),
                code="model_or_connection_denied",
            ) from None
        if isinstance(message, bytes):
            message = message.decode("utf-8")
        event = json.loads(message)
        if not isinstance(event, dict):
            raise RealtimeProviderError("服务端返回了非 JSON 对象事件", code="invalid_event")
        return event

    async def update_session(self, config: RealtimeSessionConfig | None = None) -> None:
        if config is not None:
            self.session = config
        payload: dict[str, Any] = {
            "modalities": list(self.session.modalities),
            "voice": self.session.voice,
            "instructions": self.session.instructions,
            "input_audio_format": self.session.input_audio_format,
            "output_audio_format": self.session.output_audio_format,
            "turn_detection": self._turn_detection_payload(self.session),
        }
        if self.session.tools:
            payload["tools"] = list(self.session.tools)
        await self.send_event({"type": "session.update", "session": payload})

    async def inject_vision_context_and_respond(
        self,
        *,
        scene_description: str,
        source: str | None = None,
        trigger_text: str | None = None,
    ) -> None:
        """用读图结果更新 instructions（替换上一张），再触发一轮口语回复。

        附带一条短 user 文本触发 response.create；调用方应抑制其 user.final 字幕。
        """
        from coco.modules.voice.prompts import (
            VISION_INJECT_TRIGGER_TEXT,
            merge_instructions_with_vision,
        )

        base = self._base_instructions or self.session.instructions
        merged = merge_instructions_with_vision(
            base,
            scene_description,
            source=source,
        )
        updated = RealtimeSessionConfig(
            modalities=self.session.modalities,
            voice=self.session.voice,
            instructions=merged,
            input_audio_format=self.session.input_audio_format,
            output_audio_format=self.session.output_audio_format,
            turn_detection_mode=self.session.turn_detection_mode,
            vad_threshold=self.session.vad_threshold,
            silence_duration_ms=self.session.silence_duration_ms,
            tools=self.session.tools,
        )
        await self.update_session(updated)
        # 仅 create_response 可能不触发；补隐藏触发文本，勿当用户原话展示
        text = (trigger_text or VISION_INJECT_TRIGGER_TEXT).strip()
        await self.send_event(
            {
                "type": "conversation.item.create",
                "item": {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": text}],
                },
            }
        )
        await self.create_response()

    async def send_event(self, event: Mapping[str, Any]) -> None:
        ws = self._require_ws()
        body = dict(event)
        # 官方示例用毫秒时间戳做 event_id；此处保证同毫秒内也不冲突。
        self._event_seq += 1
        body.setdefault("event_id", f"event_{int(time.time() * 1000)}_{self._event_seq}")
        await ws.send(json.dumps(body, ensure_ascii=False))

    async def append_audio(self, pcm_chunk: bytes) -> None:
        """追加 16kHz / 16bit / mono PCM 音频。"""
        await self.send_event(
            {
                "type": "input_audio_buffer.append",
                "audio": base64.b64encode(pcm_chunk).decode("ascii"),
            }
        )

    async def commit_audio_buffer(self) -> None:
        await self.send_event({"type": "input_audio_buffer.commit"})

    async def cancel_response(self) -> None:
        await self.send_event({"type": "response.cancel"})

    async def send_tool_output(self, *, call_id: str, output: str) -> None:
        """只写回 function_call_output；勿在上一轮 response.done 前紧接 response.create。"""
        await self.send_event(
            {
                "type": "conversation.item.create",
                "item": {
                    "type": "function_call_output",
                    "call_id": call_id,
                    "output": output,
                },
            }
        )

    async def create_response(
        self,
        *,
        modalities: Sequence[Literal["text", "audio"]] | None = None,
    ) -> None:
        """显式触发一轮推理；调用方须保证当前无进行中的 response。"""
        response_payload: dict[str, Any] = {
            "modalities": list(modalities) if modalities is not None else ["audio", "text"],
        }
        await self.send_event({"type": "response.create", "response": response_payload})

    async def submit_tool_result(
        self,
        *,
        call_id: str,
        output: str,
        modalities: Sequence[Literal["text", "audio"]] | None = None,
        create_followup: bool = True,
    ) -> None:
        """写回工具结果；默认立刻追问（仅当确认会话已 IDLE 时可用）。"""
        await self.send_tool_output(call_id=call_id, output=output)
        if create_followup:
            await self.create_response(modalities=modalities)

    async def inject_user_text_and_respond(self, text: str) -> None:
        """注入一条用户侧文本（如屏幕已确认），并触发生成，勿再口头追问。"""
        await self.send_event(
            {
                "type": "conversation.item.create",
                "item": {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": text}],
                },
            }
        )
        await self.create_response()

    async def events(self) -> AsyncIterator[dict[str, Any]]:
        ws = self._require_ws()
        async for message in ws:
            if isinstance(message, bytes):
                message = message.decode("utf-8")
            event = json.loads(message)
            if not isinstance(event, dict):
                continue
            yield event

    def _require_ws(self) -> ClientConnection:
        if self._ws is None:
            raise RuntimeError("WebSocket 尚未连接，请先调用 connect()")
        return self._ws

    @staticmethod
    def _turn_detection_payload(config: RealtimeSessionConfig) -> dict[str, Any] | None:
        if config.turn_detection_mode == TurnDetectionMode.MANUAL:
            return None
        if config.turn_detection_mode == TurnDetectionMode.SMART_TURN:
            return {"type": "smart_turn"}
        return {
            "type": "server_vad",
            "threshold": config.vad_threshold,
            "silence_duration_ms": config.silence_duration_ms,
        }


def _error_message(event: Mapping[str, Any]) -> str:
    error = event.get("error")
    if isinstance(error, Mapping):
        message = error.get("message")
        if isinstance(message, str) and message.strip():
            return message
    return "unknown_error"


def _close_reason(exc: websockets.exceptions.ConnectionClosedError) -> str:
    reason = (exc.reason or "").strip()
    if "Model access denied" in reason or "access denied" in reason.lower():
        return (
            "模型访问被拒绝（Model access denied）。"
            "请到阿里云百炼控制台为当前 API Key / 业务空间开通 "
            "qwen-audio-3.0-realtime-plus，并确认账户有可用额度。"
        )
    if reason:
        return f"WebSocket 连接关闭：{reason}"
    return f"WebSocket 连接关闭：code={exc.code}"


def redact_realtime_event(event: Mapping[str, Any]) -> dict[str, Any]:
    """复制事件并对音频 base64 脱敏，便于调试日志。"""
    redacted = dict(event)
    event_type = redacted.get("type")
    if event_type == "response.audio.delta":
        delta = redacted.get("delta", "")
        length = len(delta) if isinstance(delta, str) else 0
        redacted["delta"] = f"<audio b64 omitted, length={length}>"
    elif event_type == "input_audio_buffer.append":
        audio = redacted.get("audio", "")
        length = len(audio) if isinstance(audio, str) else 0
        redacted["audio"] = f"<audio b64 omitted, length={length}>"
    # 转写原文也不落普通日志
    for key in ("transcript", "text", "delta"):
        if event_type and "transcription" in str(event_type) and key in redacted:
            value = redacted.get(key)
            if isinstance(value, str) and value:
                redacted[key] = f"<text omitted, length={len(value)}>"
    return redacted
