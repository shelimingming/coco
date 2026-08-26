"""主动开场：时段规则与 instructions 拼装（不打真实库）。"""

from __future__ import annotations

from coco.modules.voice.opening import OpeningBrief, classify_period
from coco.modules.voice.prompts import build_opening_instructions


def test_classify_period_buckets() -> None:
    assert classify_period(6) == "清晨"
    assert classify_period(9) == "上午"
    assert classify_period(12) == "午间"
    assert classify_period(15) == "下午"
    assert classify_period(18) == "傍晚"
    assert classify_period(21) == "夜间"
    assert classify_period(1) == "深夜"
    assert classify_period(23) == "深夜"


def test_first_visit_full_greeting_without_highlights() -> None:
    text = build_opening_instructions(
        OpeningBrief(period="上午", visit_index=1, days_since_last=0, highlights=[])
    )
    assert "今日第 1 次进入" in text
    assert "完整问候" in text
    assert "当前没有必须开口的重要信息" in text
    assert "一次只提 1 条待办" in text
    assert "说完立刻停" in text


def test_return_visit_skips_greeting_and_mentions_due_reminder() -> None:
    text = build_opening_instructions(
        OpeningBrief(
            period="傍晚",
            visit_index=2,
            days_since_last=0,
            highlights=[
                "到点未确认的提醒：吃药（08:00）；这条上次已经提过，请换个说法轻确认，不要复读"
            ],
        )
    )
    assert "省掉寒暄" in text
    assert "吃药" in text
    assert "最多提 1 条待办" in text
    assert "适合带一句当日提醒" in text


def test_fourth_visit_and_late_night_are_minimal() -> None:
    fourth = build_opening_instructions(
        OpeningBrief(period="下午", visit_index=4, days_since_last=0, highlights=[])
    )
    assert "我在呢" in fourth
    late = build_opening_instructions(
        OpeningBrief(period="深夜", visit_index=1, days_since_last=3, highlights=[])
    )
    assert "不催促、不提待办" in late
    assert "好几天没聊了" in late
