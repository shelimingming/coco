"""next_trigger_at 时区换算单测。"""

from __future__ import annotations

from datetime import UTC, datetime, time

from coco.modules.reminders.service import compute_next_trigger_at


def test_compute_next_trigger_same_day_future() -> None:
    # 上海 10:00，当前上海 09:00 → 当天 10:00 UTC=02:00
    now = datetime(2026, 8, 9, 1, 0, tzinfo=UTC)  # 上海 09:00
    next_at = compute_next_trigger_at(
        time(10, 0),
        schedule_type="DAILY",
        now_utc=now,
        tz_name="Asia/Shanghai",
    )
    assert next_at == datetime(2026, 8, 9, 2, 0, tzinfo=UTC)


def test_compute_next_trigger_rolls_to_tomorrow() -> None:
    # 上海 10:00，当前上海 11:00 → 次日 10:00
    now = datetime(2026, 8, 9, 3, 0, tzinfo=UTC)  # 上海 11:00
    next_at = compute_next_trigger_at(
        time(10, 0),
        schedule_type="DAILY",
        now_utc=now,
        tz_name="Asia/Shanghai",
    )
    assert next_at == datetime(2026, 8, 10, 2, 0, tzinfo=UTC)


def test_compute_next_trigger_after_advances_past_due() -> None:
    due = datetime(2026, 8, 9, 2, 0, tzinfo=UTC)
    next_at = compute_next_trigger_at(
        time(10, 0),
        schedule_type="DAILY",
        after=due,
        tz_name="Asia/Shanghai",
    )
    assert next_at == datetime(2026, 8, 10, 2, 0, tzinfo=UTC)
