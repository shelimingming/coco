"""关怀摘要「知道了」已读：标记与今日未读过滤。"""

from __future__ import annotations

import time as time_mod
import uuid

import pytest
from httpx import AsyncClient

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


async def _bind_family(client: AsyncClient, parent_token: str, child_token: str) -> None:
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


@pytest.mark.asyncio
async def test_mark_care_share_read_filters_child_today(client: AsyncClient) -> None:
    parent_token = await _login(client, _unique_phone(), "parent", "读爸")
    child_token = await _login(client, _unique_phone(), "child", "读子")
    await _bind_family(client, parent_token, child_token)

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
    share_id = share.json()["id"]
    assert share.json()["read_at"] is None

    today = await client.get(
        "/v1/child/today",
        headers={"Authorization": f"Bearer {child_token}"},
    )
    assert today.status_code == 200, today.text
    assert today.json()["status"] == "ATTENTION"
    assert any(item["id"] == share_id for item in today.json()["attention_items"])

    marked = await client.post(
        f"/v1/care-shares/{share_id}/read",
        headers={"Authorization": f"Bearer {child_token}"},
    )
    assert marked.status_code == 200, marked.text
    assert marked.json()["read_at"] is not None
    first_read_at = marked.json()["read_at"]

    # 幂等：再次标记不改变已读时间
    again = await client.post(
        f"/v1/care-shares/{share_id}/read",
        headers={"Authorization": f"Bearer {child_token}"},
    )
    assert again.status_code == 200, again.text
    assert again.json()["read_at"] == first_read_at

    today_after = await client.get(
        "/v1/child/today",
        headers={"Authorization": f"Bearer {child_token}"},
    )
    assert today_after.status_code == 200, today_after.text
    body = today_after.json()
    assert all(item["id"] != share_id for item in body["attention_items"])
    # 无升级提醒时，未读清完应回落 NORMAL
    assert body["status"] == "NORMAL"

    # 详情列表仍能看到已读摘要
    listed = await client.get(
        "/v1/care-shares",
        headers={"Authorization": f"Bearer {child_token}"},
    )
    assert listed.status_code == 200, listed.text
    assert any(item["id"] == share_id and item["read_at"] is not None for item in listed.json())


@pytest.mark.asyncio
async def test_mark_care_share_read_not_found_for_other_child(client: AsyncClient) -> None:
    parent_token = await _login(client, _unique_phone(), "parent", "他爸")
    child_token = await _login(client, _unique_phone(), "child", "他子")
    other_child = await _login(client, _unique_phone(), "child", "外人")
    await _bind_family(client, parent_token, child_token)

    share = await client.post(
        "/v1/care-shares",
        headers={"Authorization": f"Bearer {parent_token}"},
        json={
            "summary": "今天心情不错。",
            "urgency": "LOW",
            "user_confirmed": True,
        },
    )
    assert share.status_code == 200, share.text
    share_id = share.json()["id"]

    denied = await client.post(
        f"/v1/care-shares/{share_id}/read",
        headers={"Authorization": f"Bearer {other_child}"},
    )
    assert denied.status_code == 404
