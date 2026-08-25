"""提醒调度状态机纯函数单测。"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from coco.models.reminder import DeliveryState, EscalationPolicy, ResponseStatus
from coco.scheduler import plan_occurrence_transition


def test_pending_goes_to_notified_1() -> None:
    now = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    plan = plan_occurrence_transition(
        delivery_state=DeliveryState.PENDING.value,
        now=now,
        first_notified_at=None,
        second_notified_at=None,
        snooze_until=None,
        reminder_revision=1,
        current_revision=1,
        escalation_policy=EscalationPolicy.NONE.value,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_delivery_state == DeliveryState.NOTIFIED_1.value
    assert plan.notify_parent is True
    assert plan.set_first_notified is True
    assert plan.increment_attempt is True


def test_notified_1_waits_before_second() -> None:
    now = datetime(2026, 8, 9, 12, 10, tzinfo=UTC)
    first_at = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    plan = plan_occurrence_transition(
        delivery_state=DeliveryState.NOTIFIED_1.value,
        now=now,
        first_notified_at=first_at,
        second_notified_at=None,
        snooze_until=None,
        reminder_revision=1,
        current_revision=1,
        escalation_policy=EscalationPolicy.NONE.value,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_delivery_state is None


def test_notified_1_escalates_to_second() -> None:
    now = datetime(2026, 8, 9, 12, 31, tzinfo=UTC)
    first_at = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    plan = plan_occurrence_transition(
        delivery_state=DeliveryState.NOTIFIED_1.value,
        now=now,
        first_notified_at=first_at,
        second_notified_at=None,
        snooze_until=None,
        reminder_revision=1,
        current_revision=1,
        escalation_policy=EscalationPolicy.NONE.value,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_delivery_state == DeliveryState.NOTIFIED_2.value
    assert plan.notify_parent is True
    assert plan.set_second_notified is True


def test_notified_2_closes_without_notifying_child_when_policy_none() -> None:
    now = datetime(2026, 8, 9, 13, 5, tzinfo=UTC)
    first_at = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    second_at = datetime(2026, 8, 9, 12, 30, tzinfo=UTC)
    plan = plan_occurrence_transition(
        delivery_state=DeliveryState.NOTIFIED_2.value,
        now=now,
        first_notified_at=first_at,
        second_notified_at=second_at,
        snooze_until=None,
        reminder_revision=1,
        current_revision=1,
        escalation_policy=EscalationPolicy.NONE.value,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_delivery_state == DeliveryState.CLOSED.value
    assert plan.next_response_status == ResponseStatus.UNANSWERED.value
    assert plan.notify_child is False
    assert plan.set_escalated is False


def test_notified_2_notifies_child_when_policy_family() -> None:
    now = datetime(2026, 8, 9, 13, 5, tzinfo=UTC)
    first_at = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    second_at = datetime(2026, 8, 9, 12, 30, tzinfo=UTC)
    plan = plan_occurrence_transition(
        delivery_state=DeliveryState.NOTIFIED_2.value,
        now=now,
        first_notified_at=first_at,
        second_notified_at=second_at,
        snooze_until=None,
        reminder_revision=1,
        current_revision=1,
        escalation_policy=EscalationPolicy.FAMILY_AFTER_TWO_UNANSWERED.value,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_delivery_state == DeliveryState.CLOSED.value
    assert plan.next_response_status == ResponseStatus.UNANSWERED.value
    assert plan.notify_child is True
    assert plan.set_escalated is True


def test_stale_revision_closes_without_notify() -> None:
    now = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    plan = plan_occurrence_transition(
        delivery_state=DeliveryState.PENDING.value,
        now=now,
        first_notified_at=None,
        second_notified_at=None,
        snooze_until=None,
        reminder_revision=1,
        current_revision=2,
        escalation_policy=EscalationPolicy.NONE.value,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_delivery_state == DeliveryState.CLOSED.value
    assert plan.notify_parent is False


def test_future_snooze_does_not_fire() -> None:
    now = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    plan = plan_occurrence_transition(
        delivery_state=DeliveryState.PENDING.value,
        now=now,
        first_notified_at=None,
        second_notified_at=None,
        snooze_until=now + timedelta(minutes=20),
        reminder_revision=1,
        current_revision=1,
        escalation_policy=EscalationPolicy.NONE.value,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_delivery_state is None


def test_expired_snooze_fires_again() -> None:
    now = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
    plan = plan_occurrence_transition(
        delivery_state=DeliveryState.PENDING.value,
        now=now,
        first_notified_at=None,
        second_notified_at=None,
        snooze_until=now - timedelta(minutes=1),
        reminder_revision=1,
        current_revision=1,
        escalation_policy=EscalationPolicy.NONE.value,
        second_delay=timedelta(minutes=30),
        escalate_delay=timedelta(minutes=30),
    )
    assert plan.next_delivery_state == DeliveryState.NOTIFIED_1.value
    assert plan.notify_parent is True
    assert plan.clear_snooze is True
