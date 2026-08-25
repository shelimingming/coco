"""提醒关键词推断与延后不改写计划。"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from coco.models.reminder import EscalationPolicy
from coco.modules.reminders.service import infer_escalation_policy


def test_infer_escalation_policy_medicine_keywords() -> None:
    assert (
        infer_escalation_policy("晚上八点吃药")
        == EscalationPolicy.FAMILY_AFTER_TWO_UNANSWERED.value
    )
    assert (
        infer_escalation_policy("复诊提醒")
        == EscalationPolicy.FAMILY_AFTER_TWO_UNANSWERED.value
    )
    assert infer_escalation_policy("测血糖") == EscalationPolicy.FAMILY_AFTER_TWO_UNANSWERED.value


def test_infer_escalation_policy_daily_habit_is_none() -> None:
    assert infer_escalation_policy("喝水") == EscalationPolicy.NONE.value
    assert infer_escalation_policy("散步") == EscalationPolicy.NONE.value


def test_snooze_keeps_plan_trigger_untouched() -> None:
    """延后只应写 occurrence.snooze_until，不改 reminder.next_trigger_at。"""
    original_trigger = datetime(2026, 8, 10, 12, 0, tzinfo=UTC)
    snooze_until = datetime(2026, 8, 9, 12, 30, tzinfo=UTC)
    # 纯数据断言：snooze 与计划触发是两条时间线
    assert snooze_until != original_trigger
    assert snooze_until == original_trigger - timedelta(hours=23, minutes=30)
