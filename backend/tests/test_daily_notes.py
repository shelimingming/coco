"""每日小记集成：设置默认、生成门禁、分享与子女可读。"""

from __future__ import annotations

import time as time_mod
import uuid
from datetime import UTC, datetime

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from coco.config import get_settings
from coco.database import get_session_factory
from coco.models.conversation import (
    Conversation,
    ConversationChannel,
    ConversationItem,
    ConversationItemKind,
    ConversationStatus,
)
from coco.models.daily_note import DailyNote, DailyNoteSource, DailyNoteStatus
from coco.models.user import User
from coco.modules.daily_notes.service import DailyNoteService

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
            "device_id": f"test-dn-{role}-{uuid.uuid4().hex[:8]}",
        },
    )
    assert login_resp.status_code == 200, login_resp.text
    return login_resp.json()["access_token"]


@pytest.mark.asyncio
async def test_daily_note_settings_defaults(client: AsyncClient) -> None:
    token = await _login(client, _unique_phone(), "parent", "小记爸")
    resp = await client.get(
        "/v1/daily-notes/settings",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["generate_enabled"] is False
    assert data["share_to_child_enabled"] is False
    assert data["generate_hour"] == 20
    assert data["gender"] == "unknown"


@pytest.mark.asyncio
async def test_daily_note_generate_empty_without_transcript(
    client: AsyncClient,
) -> None:
    token = await _login(client, _unique_phone(), "parent", "小记妈")
    resp = await client.post(
        "/v1/daily-notes/generate",
        headers={"Authorization": f"Bearer {token}"},
        json={},
    )
    assert resp.status_code == 200, resp.text
    # test 环境会等后台完成再返回终态
    data = resp.json()
    assert data["status"] == "empty"
    assert data["items"] == []
    assert "再说说今天" in data["body_text"] or "发生了什么" in data["body_text"]
    assert data["images"] == []
    assert data.get("shared_at") is None


@pytest.mark.asyncio
async def test_daily_note_generate_share_and_child_read(client: AsyncClient) -> None:
    parent_phone = _unique_phone()
    child_phone = _unique_phone()
    parent_token = await _login(client, parent_phone, "parent", "张阿姨")
    child_token = await _login(client, child_phone, "child", "小林")

    invite = await client.post(
        "/v1/family/invite",
        headers={"Authorization": f"Bearer {parent_token}"},
    )
    assert invite.status_code == 200, invite.text
    join = await client.post(
        "/v1/family/join",
        headers={"Authorization": f"Bearer {child_token}"},
        json={"code": invite.json()["code"]},
    )
    assert join.status_code == 200, join.text

    # 写入当日对话，供无 Key 时兜底抽取（复用 app 会话工厂，避开 db_engine 迁移套娃）
    me = await client.get(
        "/v1/me",
        headers={"Authorization": f"Bearer {parent_token}"},
    )
    parent_id = uuid.UUID(me.json()["id"])
    async with get_session_factory()() as session:
        conv = Conversation(
            id=uuid.uuid4(),
            user_id=parent_id,
            started_at=datetime.now(UTC),
            status=ConversationStatus.CLOSED.value,
            channel=ConversationChannel.VOICE_REALTIME.value,
            title="聊天",
        )
        session.add(conv)
        session.add(
            ConversationItem(
                id=uuid.uuid4(),
                conversation_id=conv.id,
                seq=1,
                kind=ConversationItemKind.USER.value,
                text="今天包了饺子，很好吃",
            )
        )
        session.add(
            ConversationItem(
                id=uuid.uuid4(),
                conversation_id=conv.id,
                seq=2,
                kind=ConversationItemKind.ASSISTANT.value,
                text="听起来真不错",
            )
        )
        await session.commit()

    patch = await client.patch(
        "/v1/daily-notes/settings",
        headers={"Authorization": f"Bearer {parent_token}"},
        json={"share_to_child_enabled": True, "gender": "female"},
    )
    assert patch.status_code == 200, patch.text
    assert patch.json()["share_to_child_enabled"] is True
    assert patch.json()["gender"] == "female"

    gen = await client.post(
        "/v1/daily-notes/generate",
        headers={"Authorization": f"Bearer {parent_token}"},
        json={},
    )
    assert gen.status_code == 200, gen.text
    note = gen.json()
    assert note["status"] == "ready"
    assert len(note["items"]) >= 1 or (note.get("body_text") or "").strip()
    assert note.get("title") is not None
    assert note["shared_at"] is not None

    child_today = await client.get(
        "/v1/child/daily-notes/today",
        headers={"Authorization": f"Bearer {child_token}"},
    )
    assert child_today.status_code == 200, child_today.text
    assert child_today.json()["id"] == note["id"]

    # 同日再生成覆盖，仍只有一条
    gen2 = await client.post(
        "/v1/daily-notes/generate",
        headers={"Authorization": f"Bearer {parent_token}"},
        json={},
    )
    assert gen2.status_code == 200, gen2.text
    assert gen2.json()["id"] == note["id"]

    listed = await client.get(
        "/v1/daily-notes",
        headers={"Authorization": f"Bearer {parent_token}"},
    )
    assert listed.status_code == 200, listed.text
    assert len(listed.json()["items"]) == 1


@pytest.mark.asyncio
async def test_auto_generate_skips_when_ready_exists(client: AsyncClient) -> None:
    token = await _login(client, _unique_phone(), "parent", "调度爸")
    me = await client.get("/v1/me", headers={"Authorization": f"Bearer {token}"})
    parent_id = uuid.UUID(me.json()["id"])

    # 确保有 settings
    await client.get(
        "/v1/daily-notes/settings",
        headers={"Authorization": f"Bearer {token}"},
    )

    settings = get_settings()
    service = DailyNoteService(settings)
    async with get_session_factory()() as session:
        user = await session.get(User, parent_id)
        assert user is not None
        # 先手动生成 empty，占住今日
        await service.generate_for_parent(
            session,
            user=user,
            source=DailyNoteSource.MANUAL.value,
            respect_generate_enabled=False,
        )
        # 改成 ready 模拟已有成功小记
        note = await session.scalar(select(DailyNote).where(DailyNote.parent_id == parent_id))
        assert note is not None
        note.status = DailyNoteStatus.READY.value
        note.items_json = ["已有内容"]
        note.body_text = "已有内容"
        await session.commit()

        done = await service.run_auto_generate_due(session)
        assert done == 0
