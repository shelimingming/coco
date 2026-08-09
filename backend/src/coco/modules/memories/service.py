"""长期记忆：语音侧自动写入；手动创建仍须确认。"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.errors import AppError
from coco.models.memory import Memory, MemorySource
from coco.models.user import User, UserRole
from coco.modules.memories.schemas import MemoryCreateRequest, MemoryResponse


def _to_response(memory: Memory) -> MemoryResponse:
    return MemoryResponse(
        id=memory.id,
        content=memory.content,
        category=memory.category,
        source=memory.source,
        confirmed=memory.confirmed,
        created_at=memory.created_at,
        updated_at=memory.updated_at,
    )


class MemoryService:
    async def list_for_user(self, session: AsyncSession, *, user: User) -> list[MemoryResponse]:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "memory.parent_required", "只有老人模式可以查看记忆。")
        result = await session.execute(
            select(Memory)
            .where(Memory.user_id == user.id, Memory.confirmed.is_(True))
            .order_by(Memory.created_at.desc())
        )
        return [_to_response(m) for m in result.scalars().all()]

    async def create(
        self,
        session: AsyncSession,
        *,
        user: User,
        body: MemoryCreateRequest,
        source: str = MemorySource.PARENT.value,
    ) -> MemoryResponse | dict:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "memory.parent_required", "只有老人模式可以保存记忆。")
        # 语音陪伴：静默落库，不对用户二次确认
        if source != MemorySource.VOICE.value and not body.user_confirmed:
            return {
                "status": "need_confirmation",
                "content": body.content.strip(),
                "category": body.category,
            }

        memory = Memory(
            user_id=user.id,
            content=body.content.strip(),
            category=body.category,
            source=source,
            confirmed=True,
        )
        session.add(memory)
        await session.commit()
        await session.refresh(memory)
        return _to_response(memory)

    async def delete(
        self, session: AsyncSession, *, user: User, memory_id: UUID
    ) -> dict[str, bool]:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "memory.parent_required", "只有老人模式可以删除记忆。")
        memory = await session.get(Memory, memory_id)
        if memory is None or memory.user_id != user.id:
            raise AppError(404, "memory.not_found", "找不到这条记忆，可能已被删除。")
        await session.delete(memory)
        await session.commit()
        return {"ok": True}
