"""每日小记：提取/撰写解析与兜底。"""

from __future__ import annotations

from datetime import date

from coco.providers.qwen_text import (
    build_daily_note_header_line,
    daily_note_empty_guidance,
    diary_paragraphs,
    extraction_has_diary_material,
    fallback_daily_note_extraction,
    fallback_daily_note_items,
    fallback_diary_from_extraction,
    parse_daily_note_diary_json,
    parse_daily_note_extraction_json,
    parse_daily_note_items_json,
    verify_diary_against_sources,
)


def test_parse_daily_note_items_json_ok() -> None:
    items = parse_daily_note_items_json('{"items":["今天包了饺子。","下午下楼走了走。"]}')
    assert items == ["今天包了饺子。", "下午下楼走了走。"]


def test_parse_daily_note_items_json_fence() -> None:
    items = parse_daily_note_items_json('```json\n{"items":["和邻居聊了一会儿"]}\n```')
    assert items == ["和邻居聊了一会儿"]


def test_parse_daily_note_items_empty() -> None:
    assert parse_daily_note_items_json('{"items":[]}') == []
    assert parse_daily_note_items_json("not-json") == []


def test_fallback_daily_note_items() -> None:
    transcript = "用户：今天包了饺子\n可可：真好呀\n用户：下午还下楼走了走\n"
    items = fallback_daily_note_items(transcript)
    assert len(items) == 2
    assert "饺子" in items[0]


def test_parse_extraction_and_material_gate() -> None:
    raw = """
    {"topics":["包饺子"],"events":["中午包了韭菜馅饺子"],"people":["孙女"],
     "mood":{"emotion":"高兴","evidence":"听出她高兴","uncertain":false},
     "quotes":["韭菜要早上买的才水灵"],"health_signals":[],
     "image_concepts":["厨房案板前包饺子"],"weather_mentioned":"晴"}
    """
    data = parse_daily_note_extraction_json(raw)
    assert data["topics"] == ["包饺子"]
    assert data["weather_mentioned"] == "晴"
    assert extraction_has_diary_material(data) is True
    assert extraction_has_diary_material({}) is False


def test_parse_diary_and_paragraphs() -> None:
    diary = parse_daily_note_diary_json(
        '{"title":"饺子和电话","body":"中午包了饺子。\\n下午孙女来电话。","closing":"早点睡。"}'
    )
    assert diary["title"] == "饺子和电话"
    assert diary_paragraphs(diary["body"]) == ["中午包了饺子。", "下午孙女来电话。"]
    assert diary["closing"] == "早点睡。"


def test_header_line_and_empty_guidance() -> None:
    # 2026-08-29 是星期六
    assert build_daily_note_header_line(date(2026, 8, 29)) == "8月29日 星期六"
    assert (
        build_daily_note_header_line(date(2026, 8, 29), weather_mentioned="晴")
        == "8月29日 星期六 晴"
    )
    guide = daily_note_empty_guidance()
    assert "再说说今天" in guide or "发生了什么" in guide


def test_fallback_diary_and_verify() -> None:
    extraction = fallback_daily_note_extraction("用户：今天包了饺子，韭菜很水灵\n可可：真好")
    diary = fallback_diary_from_extraction(extraction)
    assert diary["body"]
    assert "听" in diary["body"] or "记" in diary["body"]
    assert verify_diary_against_sources(
        diary=diary,
        extraction=extraction,
        transcript="用户：今天包了饺子，韭菜很水灵",
    )
    # 润色文案只要锚住事实即可通过，避免被打回流水账
    polished = {
        "title": "饺子的香味",
        "body": "今天听您说包了饺子，韭菜水灵灵的。陪在旁边听着这些，我心里也暖。",
        "closing": "我在这儿陪着。",
    }
    assert verify_diary_against_sources(
        diary=polished,
        extraction=extraction,
        transcript="用户：今天包了饺子，韭菜很水灵",
    )
