"""长期记忆：代理 Mem0；列表/删除；写入由通话结束后自动抽取。"""

from __future__ import annotations

from coco.errors import AppError
from coco.models.user import User, UserRole
from coco.modules.memories.schemas import MemoryResponse
from coco.providers.mem0_memory import Mem0MemoryClient, Mem0MemoryItem, get_mem0_client


def _to_response(item: Mem0MemoryItem) -> MemoryResponse:
    return MemoryResponse(
        id=item.id,
        content=item.content,
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

    async def list_for_user(self, *, user: User) -> list[MemoryResponse]:
        self._require_parent(user)
        items = await self._mem0().get_all(user_id=str(user.id))
        return [_to_response(item) for item in items]

    async def contents_for_inject(self, *, user_id: str, limit: int) -> list[str]:
        """语音开场注入：只取正文列表，失败返回空。"""
        items = await self._mem0().get_all(user_id=user_id, limit=limit)
        return [item.content for item in items]

    async def search_for_user(self, *, user: User, query: str) -> list[MemoryResponse]:
        self._require_parent(user)
        items = await self._mem0().search(user_id=str(user.id), query=query)
        return [_to_response(item) for item in items]

    async def delete(self, *, user: User, memory_id: str) -> dict[str, bool]:
        self._require_parent(user)
        client = self._mem0()
        # 先校验归属，避免任意父母凭 ID 删除他人记忆
        existing = await client.get(memory_id)
        if existing is None or existing.user_id != str(user.id):
            raise AppError(404, "memory.not_found", "找不到这条记忆，可能已被删除。")
        ok = await client.delete(memory_id)
        if not ok:
            raise AppError(
                503,
                "memory.delete_failed",
                "刚才没删掉。您可以再试一次，其他记忆没有受影响。",
            )
        return {"ok": True}
