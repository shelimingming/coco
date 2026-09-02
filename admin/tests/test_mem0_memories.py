"""Mem0 运营页：payload 解析与按用户分组。"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from coco.models.user import User

from coco_admin.mem0_memories.service import (
    collect_mem0_memories,
    group_memory_items,
    parse_payload,
    quote_ident,
)


def _user(*, display_name: str, role: str = "parent") -> User:
    return User(
        id=uuid4(),
        phone_hash=f"hash-{uuid4()}",
        phone_masked="138****0000",
        display_name=display_name,
        role=role,
        status="active",
    )


def test_quote_ident_rejects_injection() -> None:
    assert quote_ident("coco_memories") == '"coco_memories"'
    with pytest.raises(ValueError):
        quote_ident("coco_memories; drop table users")
    with pytest.raises(ValueError):
        quote_ident("coco-memories")


def test_parse_payload_skips_identity_and_empty() -> None:
    assert parse_payload("1", {"type": "user_identity", "user_id": "x"}) is None
    assert parse_payload("1", {"data": "   "}) is None
    assert parse_payload("", {"data": "女儿叫小林"}) is None


def test_parse_payload_reads_data_and_times() -> None:
    uid = str(uuid4())
    item = parse_payload(
        "mem-1",
        {
            "data": "女儿叫小林",
            "user_id": uid,
            "created_at": "2026-09-01T04:00:00Z",
            "updated_at": "2026-09-01T05:00:00+00:00",
        },
    )
    assert item is not None
    assert item["content"] == "女儿叫小林"
    assert item["user_id"] == uid
    assert item["created_at_label"] == "2026-09-01 12:00"
    assert item["updated_at_label"] == "2026-09-01 13:00"


def test_parse_payload_falls_back_to_memory_field() -> None:
    item = parse_payload("mem-2", {"memory": "喜欢听戏"})
    assert item is not None
    assert item["content"] == "喜欢听戏"
    assert item["user_id"] is None


def test_group_memory_items_by_user_and_count() -> None:
    parent = _user(display_name="张奶奶")
    child = _user(display_name="小李", role="child")
    items = [
        parse_payload(
            "a",
            {
                "data": "爱喝热茶",
                "user_id": str(parent.id),
                "updated_at": "2026-09-01T02:00:00Z",
            },
        ),
        parse_payload(
            "b",
            {
                "data": "女儿叫小林",
                "user_id": str(parent.id),
                "updated_at": "2026-09-01T03:00:00Z",
            },
        ),
        parse_payload(
            "c",
            {
                "data": "周末回家",
                "user_id": str(child.id),
                "updated_at": "2026-09-01T01:00:00Z",
            },
        ),
    ]
    groups = group_memory_items(
        [item for item in items if item is not None],
        {str(parent.id): parent, str(child.id): child},
    )
    assert [g["display_name"] for g in groups] == ["张奶奶", "小李"]
    assert groups[0]["count"] == 2
    assert groups[0]["role_label"] == "父母"
    assert groups[0]["memories"][0]["content"] == "女儿叫小林"
    assert groups[1]["role_label"] == "子女"


def test_group_filters_by_user_name_or_content() -> None:
    parent = _user(display_name="张奶奶")
    other = _user(display_name="王爷爷")
    items = [
        parse_payload("a", {"data": "爱喝热茶", "user_id": str(parent.id)}),
        parse_payload("b", {"data": "女儿叫小林", "user_id": str(parent.id)}),
        parse_payload("c", {"data": "爱喝热茶", "user_id": str(other.id)}),
    ]
    parsed = [item for item in items if item is not None]
    users = {str(parent.id): parent, str(other.id): other}

    by_name = group_memory_items(items=parsed, users=users, q="张奶")
    assert len(by_name) == 1
    assert by_name[0]["count"] == 2

    by_content = group_memory_items(items=parsed, users=users, q="小林")
    assert len(by_content) == 1
    assert by_content[0]["memories"][0]["content"] == "女儿叫小林"

    empty = group_memory_items(items=parsed, users=users, q="没有这条")
    assert empty == []


def test_unknown_user_keeps_orphan_memories() -> None:
    item = parse_payload("x", {"data": "孤立记忆", "user_id": str(uuid4())})
    assert item is not None
    groups = group_memory_items([item], {})
    assert groups[0]["display_name"] == "未知用户"
    assert groups[0]["count"] == 1


@pytest.mark.asyncio
async def test_collect_returns_unavailable_when_table_missing() -> None:
    result = MagicMock()
    result.first.return_value = None
    session = AsyncMock()
    session.execute = AsyncMock(return_value=result)
    data = await collect_mem0_memories(session)
    assert data["available"] is False
    assert data["groups"] == []
    assert data["total_memories"] == 0
