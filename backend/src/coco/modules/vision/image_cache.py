"""识图会话的进程内图片缓存：不落盘、带 TTL，仅供同会话追问。"""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from uuid import UUID


@dataclass(slots=True)
class CachedLookImage:
    image_bytes: bytes
    mime: str
    expires_at: float


class LookImageCache:
    """按 conversation_id 暂存原图；过期或重启后失效。"""

    def __init__(self, *, ttl_seconds: float = 15 * 60) -> None:
        self._ttl = ttl_seconds
        self._lock = threading.Lock()
        self._items: dict[UUID, CachedLookImage] = {}

    def put(self, conversation_id: UUID, *, image_bytes: bytes, mime: str) -> None:
        with self._lock:
            self._purge_locked()
            self._items[conversation_id] = CachedLookImage(
                image_bytes=image_bytes,
                mime=mime,
                expires_at=time.monotonic() + self._ttl,
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
