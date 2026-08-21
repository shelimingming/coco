"""记忆路由：列表与删除代理 Mem0。"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from coco.deps import CurrentUserDep
from coco.modules.memories.schemas import MemoryResponse
from coco.modules.memories.service import MemoryService

router = APIRouter(prefix="/v1/memories", tags=["memories"])


def get_memory_service() -> MemoryService:
    return MemoryService()


@router.get("", response_model=list[MemoryResponse])
async def list_memories(
    user: CurrentUserDep,
    service: MemoryService = Depends(get_memory_service),
) -> list[MemoryResponse]:
    return await service.list_for_user(user=user)


@router.delete("/{memory_id}")
async def delete_memory(
    memory_id: str,
    user: CurrentUserDep,
    service: MemoryService = Depends(get_memory_service),
) -> dict[str, bool]:
    return await service.delete(user=user, memory_id=memory_id)
