"""每日小记：解析与兜底。"""

from __future__ import annotations

from coco.providers.qwen_text import fallback_daily_note_items, parse_daily_note_items_json


def test_parse_daily_note_items_json_ok() -> None:
    items = parse_daily_note_items_json(
        '{"items":["今天包了饺子。","下午下楼走了走。"]}'
    )
    assert items == ["今天包了饺子。", "下午下楼走了走。"]


def test_parse_daily_note_items_json_fence() -> None:
    items = parse_daily_note_items_json(
        '```json\n{"items":["和邻居聊了一会儿"]}\n```'
    )
    assert items == ["和邻居聊了一会儿"]


def test_parse_daily_note_items_empty() -> None:
    assert parse_daily_note_items_json('{"items":[]}') == []
    assert parse_daily_note_items_json("not-json") == []


def test_fallback_daily_note_items() -> None:
    transcript = "用户：今天包了饺子\n可可：真好呀\n用户：下午还下楼走了走\n"
    items = fallback_daily_note_items(transcript)
    assert len(items) == 2
    assert "饺子" in items[0]
