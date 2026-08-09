"""对话历史 API 集成测试。"""

from __future__ import annotations

import time as time_mod
import uuid
from datetime import UTC, datetime

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from coco.models.conversation import (
    Conversation,
    ConversationChannel,
    ConversationItem,
    ConversationItemKind,
    ConversationStatus,
)
from coco.models.user import User, UserRole, UserStatus

pytestmark = pytest.mark.integration


def _unique_phone() -> str:
    n = (int(time_mod.time() * 1000) + uuid.uuid4().int) % 10_000_000_000
    return f"1{n:010d}"


async def _login(client: AsyncClient, phone: str, role: str, name: str) -> str:
    code_resp = await client.post("/v1/auth/phone/code", json={"phone": phone})
    assert code_resp.status_code == 200, code_resp.text
    challenge_id = code_resp.json()["challenge_id"]
    login_resp = await client.post(
        "/v1/auth/phone/login",
        json={
            "challenge_id": challenge_id,
            "phone": phone,
            "code": "246810",
            "role": role,
            "display_name": name,
            "device_id": f"test-{role}",
        },
    )
    assert login_resp.status_code == 200, login_resp.text
    return login_resp.json()["access_token"]


async def _me_id(client: AsyncClient, token: str) -> uuid.UUID:
    me = await client.get("/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200, me.text
    return uuid.UUID(me.json()["id"])


@pytest.mark.asyncio
async def test_parent_lists_own_conversations_only(
    client: AsyncClient,
    session_factory: async_sessionmaker[AsyncSession],
) -> None:
    parent_a = await _login(client, _unique_phone(), "parent", "爸A")
    parent_b = await _login(client, _unique_phone(), "parent", "爸B")
    child = await _login(client, _unique_phone(), "child", "子女")

    parent_a_id = await _me_id(client, parent_a)
    parent_b_id = await _me_id(client, parent_b)

    async with session_factory() as session:
        conv_a = Conversation(
            user_id=parent_a_id,
            started_at=datetime.now(UTC),
            status=ConversationStatus.CLOSED.value,
            channel=ConversationChannel.VOICE_REALTIME.value,
        )
        conv_b = Conversation(
            user_id=parent_b_id,
            started_at=datetime.now(UTC),
            status=ConversationStatus.CLOSED.value,
            channel=ConversationChannel.VOICE_REALTIME.value,
        )
        session.add_all([conv_a, conv_b])
        await session.flush()
        session.add(
            ConversationItem(
                conversation_id=conv_a.id,
                seq=1,
                kind=ConversationItemKind.USER.value,
                text="今天天气真好",
            )
        )
        session.add(
            ConversationItem(
                conversation_id=conv_a.id,
                seq=2,
                kind=ConversationItemKind.ASSISTANT.value,
                text="是呀，适合出去走走",
            )
        )
        session.add(
            ConversationItem(
                conversation_id=conv_a.id,
                seq=3,
                kind=ConversationItemKind.TOOL.value,
                tool_name="save_memory",
                arguments_json={"content": "喜欢散步"},
                result_json={"content": "喜欢散步"},
                display_summary="帮你记住：喜欢散步",
            )
        )
        await session.commit()
        conv_a_id = conv_a.id
        conv_b_id = conv_b.id

    listed = await client.get(
        "/v1/conversations",
        headers={"Authorization": f"Bearer {parent_a}"},
    )
    assert listed.status_code == 200, listed.text
    rows = listed.json()
    ids = {row["id"] for row in rows}
    assert str(conv_a_id) in ids
    assert str(conv_b_id) not in ids
    mine = next(row for row in rows if row["id"] == str(conv_a_id))
    assert "今天天气真好" in mine["preview"]
    assert "title" in mine

    detail = await client.get(
        f"/v1/conversations/{conv_a_id}",
        headers={"Authorization": f"Bearer {parent_a}"},
    )
    assert detail.status_code == 200, detail.text
    body = detail.json()
    assert "title" in body
    assert len(body["items"]) == 3
    assert body["items"][0]["kind"] == "USER"
    assert body["items"][2]["display_summary"] == "帮你记住：喜欢散步"
    # 父母端详情不暴露原始 JSON 字段
    assert "arguments_json" not in body["items"][2]

    forbidden = await client.get(
        f"/v1/conversations/{conv_a_id}",
        headers={"Authorization": f"Bearer {parent_b}"},
    )
    assert forbidden.status_code == 404

    child_list = await client.get(
        "/v1/conversations",
        headers={"Authorization": f"Bearer {child}"},
    )
    assert child_list.status_code == 403


@pytest.mark.asyncio
async def test_tool_display_and_persist_helpers(
    session_factory: async_sessionmaker[AsyncSession],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """落库 helper：创建会话、追加台词与工具、结束。"""
    from coco.database import get_session_factory as real_get_factory
    from coco.modules.conversations import service as conv_service

    monkeypatch.setattr(conv_service, "get_session_factory", lambda: session_factory)

    async with session_factory() as session:
        user = User(
            phone_hash="test-hash-" + uuid.uuid4().hex,
            phone_masked="138****0000",
            role=UserRole.PARENT.value,
            status=UserStatus.ACTIVE.value,
            display_name="测试爸",
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        user_id = user.id

    conversation_id = await conv_service.start_conversation(user_id)
    assert conversation_id is not None

    await conv_service.append_utterance(
        conversation_id,
        seq=1,
        kind=ConversationItemKind.USER.value,
        text="帮我记一下",
    )
    await conv_service.append_tool_call(
        conversation_id,
        seq=2,
        tool_name="save_memory",
        arguments={"content": "喜欢听歌"},
        result_output='{"content":"喜欢听歌"}',
    )

    async def _fake_title(**_kwargs: object) -> object:
        from coco.providers.qwen_text import TitleResult

        return TitleResult(title="记喜欢听歌", generated=True)

    monkeypatch.setattr(conv_service, "title_or_fallback", _fake_title)
    # 让 create_task 同步可等待，便于断言后台标题写入
    import asyncio

    title_tasks: list[asyncio.Task[None]] = []

    def _track_task(coro: object, name: str | None = None) -> asyncio.Task[None]:
        task = asyncio.create_task(coro, name=name)  # type: ignore[arg-type]
        title_tasks.append(task)
        return task

    monkeypatch.setattr(conv_service.asyncio, "create_task", _track_task)
    await conv_service.end_conversation(conversation_id, status=ConversationStatus.CLOSED.value)
    assert title_tasks
    await asyncio.gather(*title_tasks)

    async with session_factory() as session:
        conversation = await session.get(Conversation, conversation_id)
        assert conversation is not None
        assert conversation.status == ConversationStatus.CLOSED.value
        assert conversation.ended_at is not None
        assert conversation.title == "记喜欢听歌"
        from sqlalchemy import select

        items = (
            (
                await session.execute(
                    select(ConversationItem)
                    .where(ConversationItem.conversation_id == conversation_id)
                    .order_by(ConversationItem.seq.asc())
                )
            )
            .scalars()
            .all()
        )
        assert len(items) == 2
        assert items[0].text == "帮我记一下"
        assert items[1].display_summary == "帮你记住：喜欢听歌"

    # 恢复引用，避免影响其他用例
    monkeypatch.setattr(conv_service, "get_session_factory", real_get_factory)
