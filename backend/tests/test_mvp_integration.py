"""家庭绑定 / 提醒 / 关怀分享主链路集成测试。"""

from __future__ import annotations

import time as time_mod
import uuid

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.integration


def _unique_phone() -> str:
    # 每次生成不重复的假号码，避免复跑集成测试撞上已绑定家庭
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


async def _join_with_token(
    client: AsyncClient,
    *,
    invite_token: str,
    joiner_token: str,
) -> None:
    join = await client.post(
        "/v1/family/join",
        headers={"Authorization": f"Bearer {joiner_token}"},
        json={"token": invite_token},
    )
    assert join.status_code == 200, join.text


@pytest.mark.asyncio
async def test_family_bind_reminder_and_care_share(client: AsyncClient) -> None:
    parent_phone = _unique_phone()
    child_phone = _unique_phone()

    parent_token = await _login(client, parent_phone, "parent", "测试爸")
    child_token = await _login(client, child_phone, "child", "测试子")

    invite = await client.post(
        "/v1/family/invite",
        headers={"Authorization": f"Bearer {parent_token}"},
    )
    assert invite.status_code == 200, invite.text
    await _join_with_token(
        client,
        invite_token=invite.json()["token"],
        joiner_token=child_token,
    )

    join = await client.get(
        "/v1/family",
        headers={"Authorization": f"Bearer {child_token}"},
    )
    assert join.status_code == 200, join.text
    assert join.json()["status"] == "active"
    assert join.json()["parent_phone"] == parent_phone

    parent_view = await client.get(
        "/v1/family",
        headers={"Authorization": f"Bearer {parent_token}"},
    )
    assert parent_view.status_code == 200, parent_view.text
    assert parent_view.json()["parent_phone"] is None

    reminder = await client.post(
        "/v1/reminders",
        headers={"Authorization": f"Bearer {parent_token}"},
        json={
            "title": "吃药",
            "schedule_type": "DAILY",
            "schedule_time": "20:00:00",
            "user_confirmed": True,
        },
    )
    assert reminder.status_code == 200, reminder.text
    assert reminder.json()["title"] == "吃药"
    assert reminder.json()["next_trigger_at"] is not None

    # 未确认不应落库分享
    pending = await client.post(
        "/v1/care-shares",
        headers={"Authorization": f"Bearer {parent_token}"},
        json={
            "summary": "今天腿有些酸，目前能够正常走。",
            "urgency": "LOW",
            "user_confirmed": False,
        },
    )
    assert pending.status_code == 200
    assert pending.json()["status"] == "need_confirmation"

    share = await client.post(
        "/v1/care-shares",
        headers={"Authorization": f"Bearer {parent_token}"},
        json={
            "summary": "今天腿有些酸，目前能够正常走。",
            "urgency": "LOW",
            "user_confirmed": True,
        },
    )
    assert share.status_code == 200, share.text
    assert share.json()["parent_confirmed"] is True

    today = await client.get(
        "/v1/child/today",
        headers={"Authorization": f"Bearer {child_token}"},
    )
    assert today.status_code == 200, today.text
    body = today.json()
    assert body["status"] in {"ATTENTION", "NORMAL", "NEED_CONTACT"}
    assert any("腿" in item["summary"] for item in body["attention_items"])

    # 子女报平安：无 Key 时透传
    preview = await client.post(
        "/v1/messages/preview",
        headers={"Authorization": f"Bearer {child_token}"},
        json={"text": "刚吃过饭，马上开会"},
    )
    assert preview.status_code == 200, preview.text
    delivered = preview.json()["delivered_text"]
    send = await client.post(
        "/v1/messages",
        headers={"Authorization": f"Bearer {child_token}"},
        json={
            "original_text": "刚吃过饭，马上开会",
            "delivered_text": delivered,
        },
    )
    assert send.status_code == 200, send.text

    notes = await client.get(
        "/v1/notifications",
        headers={"Authorization": f"Bearer {parent_token}"},
    )
    assert notes.status_code == 200
    assert any(n["type"] == "CHILD_STATUS" for n in notes.json())


@pytest.mark.asyncio
async def test_child_invites_parent(client: AsyncClient) -> None:
    """子女发链接，父母加入。"""
    parent_token = await _login(client, _unique_phone(), "parent", "测试妈")
    child_token = await _login(client, _unique_phone(), "child", "测试女")

    invite = await client.post(
        "/v1/family/invite",
        headers={"Authorization": f"Bearer {child_token}"},
    )
    assert invite.status_code == 200, invite.text
    await _join_with_token(
        client,
        invite_token=invite.json()["token"],
        joiner_token=parent_token,
    )

    body = await client.get(
        "/v1/family",
        headers={"Authorization": f"Bearer {parent_token}"},
    )
    assert body.status_code == 200, body.text
    data = body.json()
    assert data["status"] == "active"
    assert data["parent_user_id"] is not None
    assert data["child_user_id"] is not None


@pytest.mark.asyncio
async def test_join_abandons_own_pending_invite(client: AsyncClient) -> None:
    """双方都生成邀请链接后，一方用对方链接仍可绑定。"""
    parent_token = await _login(client, _unique_phone(), "parent", "测试爸2")
    child_token = await _login(client, _unique_phone(), "child", "测试子2")

    parent_invite = await client.post(
        "/v1/family/invite",
        headers={"Authorization": f"Bearer {parent_token}"},
    )
    assert parent_invite.status_code == 200, parent_invite.text

    child_invite = await client.post(
        "/v1/family/invite",
        headers={"Authorization": f"Bearer {child_token}"},
    )
    assert child_invite.status_code == 200, child_invite.text

    await _join_with_token(
        client,
        invite_token=child_invite.json()["token"],
        joiner_token=parent_token,
    )

    view = await client.get(
        "/v1/family",
        headers={"Authorization": f"Bearer {parent_token}"},
    )
    assert view.status_code == 200, view.text
    assert view.json()["status"] == "active"


@pytest.mark.asyncio
async def test_join_rejects_same_role(client: AsyncClient) -> None:
    """同角色不能用对方发的链接加入。"""
    parent_a = await _login(client, _unique_phone(), "parent", "爸A")
    parent_b = await _login(client, _unique_phone(), "parent", "爸B")
    child_a = await _login(client, _unique_phone(), "child", "子A")
    child_b = await _login(client, _unique_phone(), "child", "子B")

    parent_invite = await client.post(
        "/v1/family/invite",
        headers={"Authorization": f"Bearer {parent_a}"},
    )
    assert parent_invite.status_code == 200
    wrong_parent = await client.post(
        "/v1/family/join",
        headers={"Authorization": f"Bearer {parent_b}"},
        json={"token": parent_invite.json()["token"]},
    )
    assert wrong_parent.status_code == 403
    assert wrong_parent.json()["error"]["code"] == "family.child_required"

    child_invite = await client.post(
        "/v1/family/invite",
        headers={"Authorization": f"Bearer {child_a}"},
    )
    assert child_invite.status_code == 200
    wrong_child = await client.post(
        "/v1/family/join",
        headers={"Authorization": f"Bearer {child_b}"},
        json={"token": child_invite.json()["token"]},
    )
    assert wrong_child.status_code == 403
    assert wrong_child.json()["error"]["code"] == "family.parent_required"


@pytest.mark.asyncio
async def test_invite_link_preview_and_join(client: AsyncClient) -> None:
    """邀请链接：预览免登录，token 加入绑定。"""
    parent_token = await _login(client, _unique_phone(), "parent", "链接爸")
    child_token = await _login(client, _unique_phone(), "child", "链接子")

    invite = await client.post(
        "/v1/family/invite",
        headers={"Authorization": f"Bearer {parent_token}"},
    )
    assert invite.status_code == 200, invite.text
    body = invite.json()
    assert body["token"]
    assert body["invite_url"].endswith(f"/invite/{body['token']}")

    preview = await client.get(f"/v1/family/invite/{body['token']}")
    assert preview.status_code == 200, preview.text
    assert preview.json()["target_role"] == "child"
    assert preview.json()["inviter_display_name"] == "链接爸"

    await _join_with_token(
        client,
        invite_token=body["token"],
        joiner_token=child_token,
    )

    view = await client.get(
        "/v1/family",
        headers={"Authorization": f"Bearer {child_token}"},
    )
    assert view.status_code == 200, view.text
    assert view.json()["status"] == "active"


@pytest.mark.asyncio
async def test_role_locked_after_active_family(client: AsyncClient) -> None:
    """已绑定家庭的用户不能借登录切换角色。"""
    parent_phone = _unique_phone()
    child_phone = _unique_phone()
    parent_token = await _login(client, parent_phone, "parent", "锁定爸")
    child_token = await _login(client, child_phone, "child", "锁定子")

    invite = await client.post(
        "/v1/family/invite",
        headers={"Authorization": f"Bearer {parent_token}"},
    )
    assert invite.status_code == 200
    await _join_with_token(
        client,
        invite_token=invite.json()["token"],
        joiner_token=child_token,
    )

    code_resp = await client.post("/v1/auth/phone/code", json={"phone": parent_phone})
    assert code_resp.status_code == 200
    switch = await client.post(
        "/v1/auth/phone/login",
        json={
            "challenge_id": code_resp.json()["challenge_id"],
            "phone": parent_phone,
            "code": "246810",
            "role": "child",
            "device_id": "test-switch",
        },
    )
    assert switch.status_code == 409
    assert switch.json()["error"]["code"] == "auth.role_locked"
