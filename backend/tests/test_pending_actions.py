"""通话待确认草稿：出卡展示字段与 store 幂等。"""

from __future__ import annotations

import pytest

from coco.modules.voice.pending_actions import (
    PendingActionStore,
    PendingVoiceAction,
    new_draft_id,
)
from coco.modules.voice.service import (
    _build_pending_display,
    _enrich_need_confirmation_output,
)


def test_build_reminder_display() -> None:
    display = _build_pending_display(
        "create_reminder",
        {
            "title": "吃药",
            "schedule_type": "DAILY",
            "schedule_time": "20:00",
        },
        {"status": "need_confirmation", "title": "吃药", "schedule_time": "20:00"},
    )
    assert display["title"] == "吃药"
    assert display["schedule_time"] == "20:00"
    assert display["repeat_label"] == "每天"


def test_build_share_display() -> None:
    display = _build_pending_display(
        "share_to_child",
        {"summary": "今天腿有些酸", "urgency": "LOW"},
        {"status": "need_confirmation", "summary": "今天腿有些酸"},
        share_to="小林",
    )
    assert display["summary"] == "今天腿有些酸"
    assert display["share_to"] == "小林"


def test_enrich_need_confirmation_adds_ui_hint() -> None:
    raw = '{"status":"need_confirmation","title":"吃药"}'
    enriched = _enrich_need_confirmation_output(raw)
    assert "confirmation_card_shown" in enriched
    assert "确认大卡" in enriched or "点一下" in enriched


@pytest.mark.asyncio
async def test_pending_store_take_matching_and_idempotent() -> None:
    store = PendingActionStore()
    draft_id = new_draft_id()
    action = PendingVoiceAction(
        draft_id=draft_id,
        kind="create_reminder",
        arguments={"title": "吃药", "schedule_type": "DAILY", "schedule_time": "20:00"},
        display={"title": "吃药", "schedule_time": "20:00", "repeat_label": "每天"},
    )
    await store.replace(action)
    taken = await store.take_matching(draft_id)
    assert taken is not None
    assert taken.draft_id == draft_id
    # 二次确认：无草稿，幂等
    assert await store.take_matching(draft_id) is None


@pytest.mark.asyncio
async def test_pending_store_clear_if_kind() -> None:
    store = PendingActionStore()
    action = PendingVoiceAction(
        draft_id=new_draft_id(),
        kind="share_to_child",
        arguments={"summary": "精神不错"},
        display={"summary": "精神不错", "share_to": "家人"},
    )
    await store.replace(action)
    assert await store.clear_if_kind("create_reminder") is None
    cleared = await store.clear_if_kind("share_to_child")
    assert cleared is not None
    assert cleared.kind == "share_to_child"
    assert await store.get() is None


def test_pending_to_client_payload() -> None:
    action = PendingVoiceAction(
        draft_id="d1",
        kind="create_reminder",
        arguments={},
        display={
            "title": "吃药",
            "schedule_type": "DAILY",
            "schedule_time": "20:00",
            "repeat_label": "每天",
        },
    )
    payload = action.to_client_payload()
    assert payload["draft_id"] == "d1"
    assert payload["kind"] == "create_reminder"
    assert payload["title"] == "吃药"
