"""显式记忆表 CRUD；开场注入与检索：显式优先，Mem0 补足。"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.errors import AppError
from coco.models.memory import Memory, MemoryCategory, MemorySource
from coco.models.user import User, UserRole
from coco.modules.memories.schemas import MemoryResponse
from coco.providers.mem0_memory import Mem0MemoryClient, Mem0MemoryItem, get_mem0_client

_ALLOWED_CATEGORIES = {item.value for item in MemoryCategory}


def _from_row(row: Memory) -> MemoryResponse:
    return MemoryResponse(
        id=str(row.id),
        content=row.content,
        category=row.category,
        source=row.source,
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


def _from_mem0(item: Mem0MemoryItem) -> MemoryResponse:
    return MemoryResponse(
        id=item.id,
        content=item.content,
        category="",
        source="",
        created_at=item.created_at,
        updated_at=item.updated_at,
    )


class MemoryService:
    def __init__(self, client: Mem0MemoryClient | None = None) -> None:
        self._client = client

    def _mem0(self) -> Mem0MemoryClient:
        return self._client or get_mem0_client()

    @staticmethod
    def _require_parent(user: User) -> None:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "memory.parent_required", "只有老人模式可以管理记忆。")

    async def list_for_user(self, session: AsyncSession, *, user: User) -> list[MemoryResponse]:
        self._require_parent(user)
        result = await session.execute(
            select(Memory).where(Memory.user_id == user.id).order_by(Memory.created_at.desc())
        )
        return [_from_row(row) for row in result.scalars().all()]

    async def create_from_voice(
        self,
        session: AsyncSession,
        *,
        user: User,
        content: str,
        category: str,
    ) -> MemoryResponse:
        """用户主动要求记住时落显式表；正文相同则返回已有行。"""
        self._require_parent(user)
        text = content.strip()
        if not text:
            raise AppError(400, "memory.content_required", "请告诉我要记住什么。")
        if len(text) > 2000:
            raise AppError(400, "memory.content_too_long", "这段有点长，请用一两句话说完。")
        cat = category.strip().upper()
        if cat not in _ALLOWED_CATEGORIES:
            raise AppError(400, "memory.invalid_category", "记忆类型不对，请再说一次要记住什么。")

        existing = await session.execute(
            select(Memory).where(Memory.user_id == user.id, Memory.content == text)
        )
        row = existing.scalar_one_or_none()
        if row is not None:
            return _from_row(row)

        row = Memory(
            user_id=user.id,
            content=text,
            category=cat,
            source=MemorySource.VOICE.value,
        )
        session.add(row)
        await session.commit()
        await session.refresh(row)
        return _from_row(row)

    async def contents_for_inject(
        self,
        session: AsyncSession,
        *,
        user_id: str,
        limit: int,
    ) -> list[str]:
        """开场注入：显式记忆在前，再用 Mem0 补满额度。"""
        cap = max(1, limit)
        try:
            user_uuid = UUID(user_id)
        except ValueError:
            user_uuid = None

        texts: list[str] = []
        seen: set[str] = set()
        if user_uuid is not None:
            result = await session.execute(
                select(Memory).where(Memory.user_id == user_uuid).order_by(Memory.created_at.desc())
            )
            for row in result.scalars().all():
                key = row.content.strip()
                if not key or key in seen:
                    continue
                texts.append(row.content)
                seen.add(key)
                if len(texts) >= cap:
                    return texts

        remaining = cap - len(texts)
        mem0_items = await self._mem0().get_all(user_id=user_id, limit=remaining)
        for item in mem0_items:
            key = (item.content or "").strip()
            if not key or key in seen:
                continue
            texts.append(item.content)
            seen.add(key)
            if len(texts) >= cap:
                break
        return texts

    async def search_for_user(
        self,
        session: AsyncSession,
        *,
        user: User,
        query: str,
    ) -> list[MemoryResponse]:
        self._require_parent(user)
        q = query.strip()
        merged: list[MemoryResponse] = []
        seen: set[str] = set()

        if q:
            result = await session.execute(
                select(Memory)
                .where(Memory.user_id == user.id, Memory.content.ilike(f"%{q}%"))
                .order_by(Memory.created_at.desc())
            )
            for row in result.scalars().all():
                merged.append(_from_row(row))
                seen.add(row.content.strip())

        mem0_items = await self._mem0().search(user_id=str(user.id), query=q)
        for item in mem0_items:
            key = (item.content or "").strip()
            if not key or key in seen:
                continue
            merged.append(_from_mem0(item))
            seen.add(key)
        return merged

    async def delete(self, session: AsyncSession, *, user: User, memory_id: str) -> dict[str, bool]:
        self._require_parent(user)
        try:
            uid = UUID(str(memory_id))
        except ValueError:
            raise AppError(404, "memory.not_found", "找不到这条记忆，可能已被删除。") from None
        row = await session.get(Memory, uid)
        if row is None or row.user_id != user.id:
            raise AppError(404, "memory.not_found", "找不到这条记忆，可能已被删除。")
        await session.delete(row)
        await session.commit()
        return {"ok": True}
