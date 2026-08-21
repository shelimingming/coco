"""运营统计聚合：KPI + 近 7 日趋势。"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from typing import Any

from coco.models.care import CareShare, FamilyMessage
from coco.models.conversation import Conversation
from coco.models.family import Family
from coco.models.notification import Notification
from coco.models.reminder import Reminder, ReminderOccurrence
from coco.models.user import User
from sqlalchemy import Select, cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.types import Date


def _utc_day_start(day: date) -> datetime:
    return datetime(day.year, day.month, day.day, tzinfo=UTC)


async def _count(session: AsyncSession, stmt: Select[Any]) -> int:
    result = await session.scalar(stmt)
    return int(result or 0)


async def collect_stats(session: AsyncSession, *, now: datetime | None = None) -> dict[str, Any]:
    """汇总运营看板数据；时区统一按 UTC 日界（展示层可再标注）。"""
    now = now or datetime.now(UTC)
    today = now.date()
    today_start = _utc_day_start(today)
    week_start = _utc_day_start(today - timedelta(days=6))

    users_total = await _count(session, select(func.count()).select_from(User))
    users_parent = await _count(
        session, select(func.count()).select_from(User).where(User.role == "parent")
    )
    users_child = await _count(
        session, select(func.count()).select_from(User).where(User.role == "child")
    )
    users_active = await _count(
        session, select(func.count()).select_from(User).where(User.status == "active")
    )
    users_disabled = await _count(
        session, select(func.count()).select_from(User).where(User.status == "disabled")
    )
    users_today = await _count(
        session,
        select(func.count()).select_from(User).where(User.created_at >= today_start),
    )
    users_week = await _count(
        session,
        select(func.count()).select_from(User).where(User.created_at >= week_start),
    )

    families_total = await _count(session, select(func.count()).select_from(Family))
    families_active = await _count(
        session, select(func.count()).select_from(Family).where(Family.status == "active")
    )
    families_pending = await _count(
        session, select(func.count()).select_from(Family).where(Family.status == "pending")
    )
    families_bound = await _count(
        session,
        select(func.count()).select_from(Family).where(Family.child_user_id.is_not(None)),
    )
    bound_ratio = round(families_bound / families_total, 4) if families_total else 0.0

    reminders_total = await _count(session, select(func.count()).select_from(Reminder))
    reminders_by_status: dict[str, int] = {}
    for status in ("ACTIVE", "PAUSED", "DONE", "DELETED"):
        reminders_by_status[status] = await _count(
            session,
            select(func.count()).select_from(Reminder).where(Reminder.status == status),
        )

    occ_first_today = await _count(
        session,
        select(func.count())
        .select_from(ReminderOccurrence)
        .where(ReminderOccurrence.first_notified_at >= today_start),
    )
    occ_confirmed_today = await _count(
        session,
        select(func.count())
        .select_from(ReminderOccurrence)
        .where(ReminderOccurrence.confirmed_at >= today_start),
    )
    occ_escalated_today = await _count(
        session,
        select(func.count())
        .select_from(ReminderOccurrence)
        .where(ReminderOccurrence.escalated_at >= today_start),
    )

    care_total = await _count(session, select(func.count()).select_from(CareShare))
    care_low = await _count(
        session, select(func.count()).select_from(CareShare).where(CareShare.urgency == "LOW")
    )
    care_attention = await _count(
        session,
        select(func.count()).select_from(CareShare).where(CareShare.urgency == "ATTENTION"),
    )
    care_unread = await _count(
        session,
        select(func.count()).select_from(CareShare).where(CareShare.read_at.is_(None)),
    )

    messages_total = await _count(session, select(func.count()).select_from(FamilyMessage))
    messages_child_status = await _count(
        session,
        select(func.count()).select_from(FamilyMessage).where(FamilyMessage.kind == "CHILD_STATUS"),
    )
    messages_parent_reply = await _count(
        session,
        select(func.count()).select_from(FamilyMessage).where(FamilyMessage.kind == "PARENT_REPLY"),
    )

    notifications_unread = await _count(
        session,
        select(func.count()).select_from(Notification).where(Notification.read_at.is_(None)),
    )

    conversations_total = await _count(session, select(func.count()).select_from(Conversation))
    conversations_today = await _count(
        session,
        select(func.count())
        .select_from(Conversation)
        .where(Conversation.started_at >= today_start),
    )
    conversations_by_status: dict[str, int] = {}
    for status in ("ACTIVE", "CLOSED", "ERROR"):
        conversations_by_status[status] = await _count(
            session,
            select(func.count()).select_from(Conversation).where(Conversation.status == status),
        )

    trend_days = [today - timedelta(days=i) for i in range(6, -1, -1)]
    trend = await _daily_trend(session, trend_days)

    return {
        "generated_at": now.isoformat(),
        "users": {
            "total": users_total,
            "parent": users_parent,
            "child": users_child,
            "active": users_active,
            "disabled": users_disabled,
            "today": users_today,
            "last_7_days": users_week,
        },
        "families": {
            "total": families_total,
            "active": families_active,
            "pending": families_pending,
            "bound_child": families_bound,
            "bound_ratio": bound_ratio,
        },
        "reminders": {
            "total": reminders_total,
            "by_status": reminders_by_status,
            "today": {
                "first_notified": occ_first_today,
                "confirmed": occ_confirmed_today,
                "escalated": occ_escalated_today,
            },
        },
        "care_shares": {
            "total": care_total,
            "low": care_low,
            "attention": care_attention,
            "unread": care_unread,
        },
        "messages": {
            "total": messages_total,
            "child_status": messages_child_status,
            "parent_reply": messages_parent_reply,
        },
        "notifications": {
            "unread": notifications_unread,
        },
        "conversations": {
            "total": conversations_total,
            "today": conversations_today,
            "by_status": conversations_by_status,
        },
        "trend_7d": trend,
    }


async def _daily_trend(session: AsyncSession, days: list[date]) -> list[dict[str, Any]]:
    """按日统计新用户 / 新提醒 / 新关怀 / 新消息 / 语音会话。"""
    if not days:
        return []
    start = _utc_day_start(days[0])
    end = _utc_day_start(days[-1] + timedelta(days=1))

    async def _by_day(model: Any, created_col: Any) -> dict[date, int]:
        rows = (
            await session.execute(
                select(cast(created_col, Date), func.count())
                .where(created_col >= start, created_col < end)
                .group_by(cast(created_col, Date))
            )
        ).all()
        return {row[0]: int(row[1]) for row in rows}

    users = await _by_day(User, User.created_at)
    reminders = await _by_day(Reminder, Reminder.created_at)
    care = await _by_day(CareShare, CareShare.created_at)
    messages = await _by_day(FamilyMessage, FamilyMessage.created_at)
    conversations = await _by_day(Conversation, Conversation.started_at)

    return [
        {
            "date": day.isoformat(),
            "users": users.get(day, 0),
            "reminders": reminders.get(day, 0),
            "care_shares": care.get(day, 0),
            "messages": messages.get(day, 0),
            "conversations": conversations.get(day, 0),
        }
        for day in days
    ]
