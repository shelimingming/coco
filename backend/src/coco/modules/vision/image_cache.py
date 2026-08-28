"""识图会话的进程内图片缓存：不落盘、带 TTL，仅供同会话追问。"""

from __future__ import annotations

import hashlib
import re
import threading
import time
from dataclasses import dataclass, field
from uuid import UUID


def normalize_question_key(question: str) -> str:
    """把追问收成稳定 key，用于「每问最多重识一次」。"""
    collapsed = re.sub(r"\s+", " ", (question or "").strip().lower())
    return hashlib.sha256(collapsed.encode("utf-8")).hexdigest()


@dataclass(slots=True)
class CachedLookImage:
    image_bytes: bytes
    mime: str
    expires_at: float
    # 多轮证据：首轮 scene + 后续重识补充
    accumulated_observation: str = ""
    # 已重识过的问题 key，避免同一问反复打视觉模型
    reanalyzed_keys: set[str] = field(default_factory=set)


class LookImageCache:
    """按 conversation_id 暂存原图；过期或重启后失效。"""

    def __init__(self, *, ttl_seconds: float = 15 * 60) -> None:
        self._ttl = ttl_seconds
        self._lock = threading.Lock()
        self._items: dict[UUID, CachedLookImage] = {}

    def put(
        self,
        conversation_id: UUID,
        *,
        image_bytes: bytes,
        mime: str,
        observation: str = "",
    ) -> None:
        with self._lock:
            self._purge_locked()
            self._items[conversation_id] = CachedLookImage(
                image_bytes=image_bytes,
                mime=mime,
                expires_at=time.monotonic() + self._ttl,
                accumulated_observation=observation.strip(),
                reanalyzed_keys=set(),
            )

    def get(self, conversation_id: UUID) -> CachedLookImage | None:
        with self._lock:
            self._purge_locked()
            item = self._items.get(conversation_id)
            if item is None:
                return None
            if item.expires_at <= time.monotonic():
                self._items.pop(conversation_id, None)
                return None
            return item

    def remember_reanalyze(
        self,
        conversation_id: UUID,
        *,
        question_key: str,
        observation: str,
    ) -> CachedLookImage | None:
        """写入补充观察并标记该问已重识；条目不存在则返回 None。"""
        with self._lock:
            self._purge_locked()
            item = self._items.get(conversation_id)
            if item is None or item.expires_at <= time.monotonic():
                self._items.pop(conversation_id, None)
                return None
            item.accumulated_observation = observation.strip()
            item.reanalyzed_keys.add(question_key)
            return item

    def discard(self, conversation_id: UUID) -> None:
        with self._lock:
            self._items.pop(conversation_id, None)

    def _purge_locked(self) -> None:
        now = time.monotonic()
        expired = [k for k, v in self._items.items() if v.expires_at <= now]
        for key in expired:
            self._items.pop(key, None)


# 进程单例：重启后追问需重新拍照
look_image_cache = LookImageCache()
