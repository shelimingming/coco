"""提醒调度状态机纯函数单测。"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from coco.models.reminder import OccurrenceState
from coco.scheduler import plan_occurrence_transition


def test_waiting_goes_to_first_reminder() -> None:
    now = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    plan = plan_occurrence_transition(
        state=OccurrenceState.WAITING.value,
        now=now,
        first_notified_at=None,
        second_notified_at=None,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_state == OccurrenceState.FIRST_REMINDER.value
    assert plan.notify_parent is True
    assert plan.set_first_notified is True


def test_first_reminder_waits_before_second() -> None:
    now = datetime(2026, 8, 9, 12, 10, tzinfo=UTC)
    first_at = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    plan = plan_occurrence_transition(
        state=OccurrenceState.FIRST_REMINDER.value,
        now=now,
        first_notified_at=first_at,
        second_notified_at=None,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_state is None


def test_first_reminder_escalates_to_second() -> None:
    now = datetime(2026, 8, 9, 12, 31, tzinfo=UTC)
    first_at = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    plan = plan_occurrence_transition(
        state=OccurrenceState.FIRST_REMINDER.value,
        now=now,
        first_notified_at=first_at,
        second_notified_at=None,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_state == OccurrenceState.SECOND_REMINDER.value
    assert plan.notify_parent is True
    assert plan.set_second_notified is True


def test_second_reminder_escalates_to_child() -> None:
    now = datetime(2026, 8, 9, 13, 5, tzinfo=UTC)
    first_at = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    second_at = datetime(2026, 8, 9, 12, 30, tzinfo=UTC)
    plan = plan_occurrence_transition(
        state=OccurrenceState.SECOND_REMINDER.value,
        now=now,
        first_notified_at=first_at,
        second_notified_at=second_at,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_state == OccurrenceState.ESCALATED.value
    assert plan.notify_child is True
    assert plan.set_escalated is True
