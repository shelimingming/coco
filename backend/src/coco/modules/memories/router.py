"""记忆路由：只列/删显式表中用户主动记住的内容。"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from coco.deps import CurrentUserDep, SessionDep
from coco.modules.memories.schemas import MemoryResponse
from coco.modules.memories.service import MemoryService

router = APIRouter(prefix="/v1/memories", tags=["memories"])


def get_memory_service() -> MemoryService:
    return MemoryService()


@router.get("", response_model=list[MemoryResponse])
async def list_memories(
    session: SessionDep,
    user: CurrentUserDep,
    service: MemoryService = Depends(get_memory_service),
) -> list[MemoryResponse]:
    return await service.list_for_user(session, user=user)


@router.delete("/{memory_id}")
async def delete_memory(
    memory_id: str,
    session: SessionDep,
    user: CurrentUserDep,
    service: MemoryService = Depends(get_memory_service),
) -> dict[str, bool]:
    return await service.delete(session, user=user, memory_id=memory_id)
