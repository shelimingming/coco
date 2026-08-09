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
    code = invite.json()["code"]

    join = await client.post(
        "/v1/family/join",
        headers={"Authorization": f"Bearer {child_token}"},
        json={"code": code},
    )
    assert join.status_code == 200, join.text
    assert join.json()["status"] == "active"

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
