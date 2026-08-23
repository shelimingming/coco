"""Mem0 OSS 适配层：百炼 LLM/Embedding + 同库 pgvector。

无 Key 或调用失败时降级为空结果，不拖垮语音挂断与记忆页。
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from functools import lru_cache
from pathlib import Path
from typing import Any

from coco.config import Settings, get_settings
from coco.observability.llm_trace import (
    PURPOSE_MEM0_EXTRACT,
    PURPOSE_MEM0_SEARCH,
    record_llm_trace,
)
from coco.providers.mem0_prompts import COCO_MEMORY_CUSTOM_INSTRUCTIONS

logger = logging.getLogger(__name__)

# 必须在 import mem0 前关闭 PostHog 匿名遥测（父母对话隐私）
os.environ.setdefault("MEM0_TELEMETRY", "False")


@dataclass(frozen=True)
class Mem0MemoryItem:
    """适配层统一记忆条目，屏蔽 mem0 返回字段差异。"""

    id: str
    content: str
    user_id: str | None
    created_at: datetime | None
    updated_at: datetime | None
    score: float | None = None


def _mem0_item_payload(item: Mem0MemoryItem) -> dict[str, Any]:
    """调试落库用的精简字段，避免把整份 mem0 对象塞进 JSON。"""
    return {
        "id": item.id,
        "content": item.content,
        "score": item.score,
    }


def _parse_datetime(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    text = str(value).strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def _normalize_item(raw: dict[str, Any]) -> Mem0MemoryItem | None:
    memory_id = str(raw.get("id") or "").strip()
    content = str(raw.get("memory") or raw.get("data") or raw.get("text") or "").strip()
    if not memory_id or not content:
        return None
    user_id = raw.get("user_id")
    if user_id is None and isinstance(raw.get("payload"), dict):
        user_id = raw["payload"].get("user_id")
    score_raw = raw.get("score")
    score = float(score_raw) if score_raw is not None else None
    return Mem0MemoryItem(
        id=memory_id,
        content=content,
        user_id=str(user_id) if user_id is not None else None,
        created_at=_parse_datetime(raw.get("created_at")),
        updated_at=_parse_datetime(raw.get("updated_at")),
        score=score,
    )


def _results_list(payload: Any) -> list[dict[str, Any]]:
    if payload is None:
        return []
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        results = payload.get("results")
        if isinstance(results, list):
            return [item for item in results if isinstance(item, dict)]
    return []


class Mem0MemoryClient:
    """对 AsyncMemory 的薄封装；所有公开方法吞异常并返回安全空值。"""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._memory: Any | None = None
        self._init_lock = asyncio.Lock()
        self._init_failed = False

    @property
    def available(self) -> bool:
        return self._settings.mem0_available and not self._init_failed

    async def _ensure_memory(self) -> Any | None:
        if not self._settings.mem0_available or self._init_failed:
            return None
        if self._memory is not None:
            return self._memory
        async with self._init_lock:
            if self._memory is not None:
                return self._memory
            if self._init_failed:
                return None
            try:
                self._memory = await self._build_memory()
            except Exception:
                self._init_failed = True
                logger.exception("mem0_init_failed")
                return None
            return self._memory

    async def _build_memory(self) -> Any:
        from mem0 import AsyncMemory

        settings = self._settings
        api_key = settings.aliyun_api_key
        assert api_key is not None
        key = api_key.get_secret_value().strip()
        history_path = Path(settings.mem0_history_db_path)
        history_path.parent.mkdir(parents=True, exist_ok=True)

        config: dict[str, Any] = {
            "llm": {
                "provider": "openai",
                "config": {
                    "model": settings.text_model,
                    "api_key": key,
                    "openai_base_url": settings.aliyun_compatible_base_url,
                    "temperature": 0.1,
                },
            },
            "embedder": {
                "provider": "openai",
                "config": {
                    "model": settings.mem0_embedding_model,
                    "api_key": key,
                    "openai_base_url": settings.aliyun_compatible_base_url,
                    "embedding_dims": settings.mem0_embedding_dims,
                },
            },
            "vector_store": {
                "provider": "pgvector",
                "config": {
                    "connection_string": settings.mem0_pg_connection_string(),
                    "collection_name": settings.mem0_collection_name,
                    "embedding_model_dims": settings.mem0_embedding_dims,
                    "hnsw": True,
                    "minconn": settings.mem0_pg_minconn,
                    "maxconn": settings.mem0_pg_maxconn,
                },
            },
            "history_db_path": str(history_path),
            "custom_instructions": COCO_MEMORY_CUSTOM_INSTRUCTIONS,
        }
        memory = AsyncMemory.from_config(config)
        if asyncio.iscoroutine(memory):
            memory = await memory
        return memory

    async def add_from_messages(
        self,
        *,
        user_id: str,
        messages: list[dict[str, str]],
    ) -> list[Mem0MemoryItem]:
        """通话结束后自动抽取；infer=True 由 Mem0 决定 ADD/UPDATE/NOOP。"""
        if not messages:
            return []
        started = datetime.now(UTC)
        t0 = time.perf_counter()
        memory = await self._ensure_memory()
        if memory is None:
            await record_llm_trace(
                purpose=PURPOSE_MEM0_EXTRACT,
                modality="text",
                model=self._settings.text_model,
                status="skipped",
                request_json={"messages": messages},
                error_message="Mem0 不可用，跳过抽取",
                started_at=started,
            )
            return []
        try:
            raw = await memory.add(
                messages,
                user_id=user_id,
                infer=True,
                prompt=COCO_MEMORY_CUSTOM_INSTRUCTIONS,
            )
            items = [
                item
                for item in (_normalize_item(row) for row in _results_list(raw))
                if item is not None
            ]
            await record_llm_trace(
                purpose=PURPOSE_MEM0_EXTRACT,
                modality="text",
                model=self._settings.text_model,
                status="ok",
                latency_ms=int((time.perf_counter() - t0) * 1000),
                request_json={"messages": messages},
                response_json={"memories": [_mem0_item_payload(item) for item in items]},
                started_at=started,
            )
            return items
        except Exception as exc:
            logger.exception("mem0_add_failed user_id=%s", user_id)
            await record_llm_trace(
                purpose=PURPOSE_MEM0_EXTRACT,
                modality="text",
                model=self._settings.text_model,
                status="error",
                latency_ms=int((time.perf_counter() - t0) * 1000),
                request_json={"messages": messages},
                error_message=str(exc),
                started_at=started,
            )
            return []

    async def search(
        self,
        *,
        user_id: str,
        query: str,
        limit: int | None = None,
    ) -> list[Mem0MemoryItem]:
        q = query.strip()
        if not q:
            return []
        started = datetime.now(UTC)
        t0 = time.perf_counter()
        memory = await self._ensure_memory()
        if memory is None:
            await record_llm_trace(
                purpose=PURPOSE_MEM0_SEARCH,
                modality="embedding",
                model=self._settings.mem0_embedding_model,
                status="skipped",
                request_json={"query": q},
                error_message="Mem0 不可用，跳过检索",
                started_at=started,
            )
            return []
        top_k = limit if limit is not None else self._settings.mem0_search_limit
        try:
            raw = await memory.search(
                q,
                filters={"user_id": user_id},
                top_k=max(1, top_k),
            )
            items = [
                item
                for item in (_normalize_item(row) for row in _results_list(raw))
                if item is not None
            ]
            await record_llm_trace(
                purpose=PURPOSE_MEM0_SEARCH,
                modality="embedding",
                model=self._settings.mem0_embedding_model,
                status="ok",
                latency_ms=int((time.perf_counter() - t0) * 1000),
                request_json={"query": q, "limit": top_k},
                response_json={"hits": [_mem0_item_payload(item) for item in items]},
                started_at=started,
            )
            return items
        except Exception as exc:
            logger.exception("mem0_search_failed user_id=%s", user_id)
            await record_llm_trace(
                purpose=PURPOSE_MEM0_SEARCH,
                modality="embedding",
                model=self._settings.mem0_embedding_model,
                status="error",
                latency_ms=int((time.perf_counter() - t0) * 1000),
                request_json={"query": q},
                error_message=str(exc),
                started_at=started,
            )
            return []

    async def get_all(
        self,
        *,
        user_id: str,
        limit: int | None = None,
    ) -> list[Mem0MemoryItem]:
        memory = await self._ensure_memory()
        if memory is None:
            return []
        top_k = limit if limit is not None else self._settings.mem0_inject_limit
        try:
            raw = await memory.get_all(
                filters={"user_id": user_id},
                top_k=max(1, top_k),
            )
            return [
                item
                for item in (_normalize_item(row) for row in _results_list(raw))
                if item is not None
            ]
        except Exception:
            logger.exception("mem0_get_all_failed user_id=%s", user_id)
            return []

    async def get(self, memory_id: str) -> Mem0MemoryItem | None:
        memory = await self._ensure_memory()
        if memory is None:
            return None
        try:
            raw = await memory.get(memory_id)
            if not isinstance(raw, dict):
                return None
            return _normalize_item(raw)
        except Exception:
            logger.exception("mem0_get_failed memory_id=%s", memory_id)
            return None

    async def delete(self, memory_id: str) -> bool:
        memory = await self._ensure_memory()
        if memory is None:
            return False
        try:
            await memory.delete(memory_id)
            return True
        except Exception:
            logger.exception("mem0_delete_failed memory_id=%s", memory_id)
            return False


@lru_cache
def get_mem0_client() -> Mem0MemoryClient:
    """进程内单例；Settings 变更需清缓存（测试可直接 new）。"""
    return Mem0MemoryClient(get_settings())
