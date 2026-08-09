"""通话内待确认草稿：提醒创建 / 分享子女，点卡或语音二选一确认。"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import uuid4

# 草稿超时后点卡无效，避免误确认过期内容
_PENDING_TTL = timedelta(minutes=5)

CONFIRMABLE_KINDS = frozenset({"create_reminder", "share_to_child"})


@dataclass
class PendingVoiceAction:
    draft_id: str
    kind: str
    arguments: dict[str, Any]
    display: dict[str, Any]
    created_at: datetime = field(default_factory=lambda: datetime.now(UTC))

    def expired(self, *, now: datetime | None = None) -> bool:
        ts = now or datetime.now(UTC)
        return ts - self.created_at > _PENDING_TTL

    def to_client_payload(self) -> dict[str, Any]:
        return {
            "draft_id": self.draft_id,
            "kind": self.kind,
            **self.display,
        }


class PendingActionStore:
    """单次 Realtime 连接作用域的 pending（并发安全）。"""

    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._pending: PendingVoiceAction | None = None

    async def replace(self, action: PendingVoiceAction) -> PendingVoiceAction:
        async with self._lock:
            self._pending = action
            return action

    async def get(self) -> PendingVoiceAction | None:
        async with self._lock:
            if self._pending is None:
                return None
            if self._pending.expired():
                self._pending = None
                return None
            return self._pending

    async def clear(self) -> None:
        async with self._lock:
            self._pending = None

    async def take_matching(self, draft_id: str) -> PendingVoiceAction | None:
        """取出并清空匹配的未过期草稿；不匹配则不动。"""
        async with self._lock:
            pending = self._pending
            if pending is None:
                return None
            if pending.expired():
                self._pending = None
                return None
            if pending.draft_id != draft_id:
                return None
            self._pending = None
            return pending

    async def clear_if_kind(self, kind: str) -> PendingVoiceAction | None:
        """若当前草稿 kind 匹配则清空并返回原草稿（供下行带 draft_id）。"""
        async with self._lock:
            if self._pending is None or self._pending.kind != kind:
                return None
            action = self._pending
            self._pending = None
            return action


def new_draft_id() -> str:
    return str(uuid4())
