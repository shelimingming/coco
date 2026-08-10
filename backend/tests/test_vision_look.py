"""识图结果解析与看不清兜底。"""

from __future__ import annotations

from coco.providers.qwen_vision import parse_look_content, unclear_look_result


def test_parse_look_content_high() -> None:
    result = parse_look_content(
        '{"confidence":"high","headline":"保质期到 2026年8月18日",'
        '"detail":"今天还没有过期。","safety_note":"包装鼓起不要食用。"}'
    )
    assert result.confidence == "high"
    assert "2026" in result.headline
    assert "过期" in result.detail
    assert "鼓起" in result.safety_note


def test_parse_look_content_low_clears_headline() -> None:
    result = parse_look_content(
        '{"confidence":"low","headline":"可能是日期","detail":"","safety_note":""}'
    )
    assert result.confidence == "low"
    assert result.headline == ""
    assert "看不太清" in result.detail


def test_parse_look_content_fenced_json() -> None:
    result = parse_look_content(
        '```json\n{"confidence":"high","headline":"快递柜通知",'
        '"detail":"今晚前取件。","safety_note":""}\n```'
    )
    assert result.confidence == "high"
    assert result.headline == "快递柜通知"


def test_unclear_look_result() -> None:
    result = unclear_look_result()
    assert result.confidence == "low"
    assert result.headline == ""
    assert "看不太清" in result.detail
