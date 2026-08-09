"""记忆路由。"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends

from coco.deps import CurrentUserDep, SessionDep
from coco.modules.memories.schemas import MemoryCreateRequest, MemoryResponse
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


@router.post("", response_model=None)
async def create_memory(
    body: MemoryCreateRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: MemoryService = Depends(get_memory_service),
) -> MemoryResponse | dict:
    return await service.create(session, user=user, body=body)


@router.delete("/{memory_id}")
async def delete_memory(
    memory_id: UUID,
    session: SessionDep,
    user: CurrentUserDep,
    service: MemoryService = Depends(get_memory_service),
) -> dict[str, bool]:
    return await service.delete(session, user=user, memory_id=memory_id)
