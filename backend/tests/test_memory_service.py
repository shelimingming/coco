"""记忆服务：代理 Mem0，校验删除归属与降级。"""

from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from coco.errors import AppError
from coco.models.user import User, UserRole, UserStatus
from coco.modules.memories.service import MemoryService
from coco.providers.mem0_memory import Mem0MemoryItem


def _parent() -> User:
    return User(
        id=uuid4(),
        phone_hash="hash",
        phone_masked="138****0000",
        display_name="测试父母",
        role=UserRole.PARENT.value,
        status=UserStatus.ACTIVE.value,
    )


def _child() -> User:
    return User(
        id=uuid4(),
        phone_hash="hash2",
        phone_masked="139****0000",
        display_name="测试子女",
        role=UserRole.CHILD.value,
        status=UserStatus.ACTIVE.value,
    )


@pytest.mark.asyncio
async def test_list_for_user_maps_mem0_items() -> None:
    parent = _parent()
    now = datetime.now(UTC)
    client = AsyncMock()
    client.get_all = AsyncMock(
        return_value=[
            Mem0MemoryItem(
                id="m1",
                content="喜欢吃红烧肉",
                user_id=str(parent.id),
                created_at=now,
                updated_at=now,
            )
        ]
    )
    items = await MemoryService(client).list_for_user(user=parent)
    assert len(items) == 1
    assert items[0].id == "m1"
    assert items[0].content == "喜欢吃红烧肉"


@pytest.mark.asyncio
async def test_list_empty_when_mem0_unavailable() -> None:
    parent = _parent()
    client = AsyncMock()
    client.get_all = AsyncMock(return_value=[])
    items = await MemoryService(client).list_for_user(user=parent)
    assert items == []


@pytest.mark.asyncio
async def test_delete_rejects_other_users_memory() -> None:
    parent = _parent()
    client = AsyncMock()
    client.get = AsyncMock(
        return_value=Mem0MemoryItem(
            id="m1",
            content="别人的记忆",
            user_id=str(uuid4()),
            created_at=None,
            updated_at=None,
        )
    )
    client.delete = AsyncMock(return_value=True)
    with pytest.raises(AppError) as exc:
        await MemoryService(client).delete(user=parent, memory_id="m1")
    assert exc.value.code == "memory.not_found"
    client.delete.assert_not_awaited()


@pytest.mark.asyncio
async def test_delete_ok_for_owner() -> None:
    parent = _parent()
    client = AsyncMock()
    client.get = AsyncMock(
        return_value=Mem0MemoryItem(
            id="m1",
            content="自己的记忆",
            user_id=str(parent.id),
            created_at=None,
            updated_at=None,
        )
    )
    client.delete = AsyncMock(return_value=True)
    result = await MemoryService(client).delete(user=parent, memory_id="m1")
    assert result == {"ok": True}
    client.delete.assert_awaited_once_with("m1")


@pytest.mark.asyncio
async def test_child_forbidden() -> None:
    with pytest.raises(AppError) as exc:
        await MemoryService(AsyncMock()).list_for_user(user=_child())
    assert exc.value.status_code == 403
