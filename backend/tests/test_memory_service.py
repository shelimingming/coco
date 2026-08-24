"""记忆服务：显式表列表/删除/去重；注入显式优先。"""

from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from coco.errors import AppError
from coco.models.memory import Memory, MemoryCategory, MemorySource
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


def _row(user_id, content: str = "女儿叫小林") -> Memory:
    return Memory(
        id=uuid4(),
        user_id=user_id,
        content=content,
        category=MemoryCategory.FAMILY.value,
        source=MemorySource.VOICE.value,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )


def _execute_result(*, rows: list[Memory] | None = None, one: Memory | None = None) -> MagicMock:
    result = MagicMock()
    result.scalars.return_value.all.return_value = rows or []
    result.scalar_one_or_none.return_value = one
    return result


@pytest.mark.asyncio
async def test_list_for_user_returns_explicit_rows() -> None:
    parent = _parent()
    row = _row(parent.id)
    session = AsyncMock()
    session.execute = AsyncMock(return_value=_execute_result(rows=[row]))
    items = await MemoryService(AsyncMock()).list_for_user(session, user=parent)
    assert len(items) == 1
    assert items[0].content == "女儿叫小林"
    assert items[0].category == MemoryCategory.FAMILY.value
    assert items[0].source == MemorySource.VOICE.value


@pytest.mark.asyncio
async def test_list_empty() -> None:
    parent = _parent()
    session = AsyncMock()
    session.execute = AsyncMock(return_value=_execute_result(rows=[]))
    items = await MemoryService(AsyncMock()).list_for_user(session, user=parent)
    assert items == []


@pytest.mark.asyncio
async def test_create_from_voice_inserts() -> None:
    parent = _parent()
    session = AsyncMock()
    session.execute = AsyncMock(return_value=_execute_result(one=None))
    session.commit = AsyncMock()
    session.refresh = AsyncMock()
    added: list[Memory] = []
    session.add = MagicMock(side_effect=lambda obj: added.append(obj))

    item = await MemoryService(AsyncMock()).create_from_voice(
        session,
        user=parent,
        content=" 喜欢晚饭后散步 ",
        category="preference",
    )
    assert added[0].content == "喜欢晚饭后散步"
    assert added[0].category == MemoryCategory.PREFERENCE.value
    assert added[0].source == MemorySource.VOICE.value
    assert item.content == "喜欢晚饭后散步"
    session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_create_from_voice_skips_duplicate() -> None:
    parent = _parent()
    existing = _row(parent.id, "喜欢晚饭后散步")
    session = AsyncMock()
    session.execute = AsyncMock(return_value=_execute_result(one=existing))
    session.add = MagicMock()
    item = await MemoryService(AsyncMock()).create_from_voice(
        session,
        user=parent,
        content="喜欢晚饭后散步",
        category="PREFERENCE",
    )
    assert item.id == str(existing.id)
    session.add.assert_not_called()


@pytest.mark.asyncio
async def test_contents_for_inject_explicit_first() -> None:
    parent = _parent()
    explicit = _row(parent.id, "女儿叫小林")
    session = AsyncMock()
    session.execute = AsyncMock(return_value=_execute_result(rows=[explicit]))
    client = AsyncMock()
    client.get_all = AsyncMock(
        return_value=[
            Mem0MemoryItem(
                id="m0",
                content="喜欢听老歌",
                user_id=str(parent.id),
                created_at=None,
                updated_at=None,
            )
        ]
    )
    texts = await MemoryService(client).contents_for_inject(
        session,
        user_id=str(parent.id),
        limit=5,
    )
    assert texts[0] == "女儿叫小林"
    assert "喜欢听老歌" in texts


@pytest.mark.asyncio
async def test_delete_rejects_other_users_memory() -> None:
    parent = _parent()
    session = AsyncMock()
    session.get = AsyncMock(return_value=_row(uuid4()))
    session.delete = AsyncMock()
    with pytest.raises(AppError) as exc:
        await MemoryService(AsyncMock()).delete(
            session,
            user=parent,
            memory_id=str(uuid4()),
        )
    assert exc.value.code == "memory.not_found"
    session.delete.assert_not_awaited()


@pytest.mark.asyncio
async def test_delete_ok_for_owner() -> None:
    parent = _parent()
    row = _row(parent.id)
    session = AsyncMock()
    session.get = AsyncMock(return_value=row)
    session.delete = AsyncMock()
    session.commit = AsyncMock()
    result = await MemoryService(AsyncMock()).delete(
        session,
        user=parent,
        memory_id=str(row.id),
    )
    assert result == {"ok": True}
    session.delete.assert_awaited_once_with(row)


@pytest.mark.asyncio
async def test_child_forbidden() -> None:
    with pytest.raises(AppError) as exc:
        await MemoryService(AsyncMock()).list_for_user(AsyncMock(), user=_child())
    assert exc.value.status_code == 403
