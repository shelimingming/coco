"""主动开场简报：只聚合事实，不调模型。

时段、今日第几次进入、距上次通话天数、按优先级排列的重要信息，
供 instructions 注入；去重靠「未确认 / 未读」，不另建状态表。
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings
from coco.models.care import FamilyMessage, FamilyMessageKind
from coco.models.conversation import Conversation, ConversationChannel
from coco.models.reminder import ReminderStatus, ResponseStatus
from coco.models.user import User
from coco.modules.family.service import get_family
from coco.modules.reminders.service import ReminderService

logger = logging.getLogger(__name__)

# 同一次开场最多带两条，避免变成播报机
_MAX_HIGHLIGHTS = 2


@dataclass(frozen=True)
class OpeningBrief:
    """本次建连的开场事实；由规则拼进 instructions，不写死台词。"""

    period: str
    visit_index: int
    days_since_last: int
    highlights: list[str] = field(default_factory=list)


def classify_period(hour: int) -> str:
    """按本地小时切时段，驱动开场语气。"""
    if 5 <= hour < 8:
        return "清晨"
    if 8 <= hour < 11:
        return "上午"
    if 11 <= hour < 13:
        return "午间"
    if 13 <= hour < 17:
        return "下午"
    if 17 <= hour < 19:
        return "傍晚"
    if 19 <= hour < 23:
        return "夜间"
    return "深夜"


def _local_now(tz_name: str) -> datetime:
    return datetime.now(UTC).astimezone(ZoneInfo(tz_name))


def _format_local_clock(when: datetime, tz_name: str) -> str:
    local = when.astimezone(ZoneInfo(tz_name))
    return f"{local.hour:02d}:{local.minute:02d}"


async def _visit_stats(
    session: AsyncSession,
    *,
    user: User,
    now_local: datetime,
) -> tuple[int, int]:
    """今日第几次进入、距上次通话天数。

    start_conversation 已写入本通，计数包含当前这次；间隔用上一通。
    """
    result = await session.execute(
        select(Conversation)
        .where(
            Conversation.user_id == user.id,
            Conversation.channel == ConversationChannel.VOICE_REALTIME.value,
        )
        .order_by(Conversation.started_at.desc())
    )
    rows = list(result.scalars().all())
    today_start = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
    visit_index = 0
    for conv in rows:
        started = conv.started_at
        if started.tzinfo is None:
            started = started.replace(tzinfo=UTC)
        local_started = started.astimezone(now_local.tzinfo)
        if local_started >= today_start:
            visit_index += 1

    if visit_index < 1:
        visit_index = 1

    days_since_last = 0
    # rows[0] 是刚建的本通；用下一通算「好几天没聊」
    previous = rows[1] if len(rows) > 1 else None
    if previous is not None:
        last_at = previous.ended_at or previous.started_at
        if last_at.tzinfo is None:
            last_at = last_at.replace(tzinfo=UTC)
        last_local = last_at.astimezone(now_local.tzinfo)
        days_since_last = max(0, (now_local.date() - last_local.date()).days)
    return visit_index, days_since_last


async def _collect_highlights(
    session: AsyncSession,
    *,
    user: User,
    settings: Settings,
    tz_name: str,
    period: str,
    visit_index: int,
) -> list[str]:
    """按优先级收集最多两条；深夜 / 第 4 次起不追待办。"""
    if period == "深夜" or visit_index >= 4:
        return []

    items: list[str] = []
    reminder_svc = ReminderService(settings)

    try:
        occurrences = await reminder_svc.list_open_occurrences(session, user=user)
    except Exception:
        logger.warning("opening_list_occurrences_failed user_id=%s", user.id, exc_info=True)
        occurrences = []

    for occ in occurrences:
        if occ.response_status != ResponseStatus.NONE.value:
            continue
        title = (occ.title_snapshot or "").strip() or "提醒"
        clock = _format_local_clock(occ.due_at, tz_name)
        note = f"到点未确认的提醒：{title}（{clock}）"
        if visit_index >= 2:
            note += "；这条上次已经提过，请换个说法轻确认，不要复读"
        items.append(note)
        if len(items) >= _MAX_HIGHLIGHTS:
            return items

    # 午间 / 夜间偏关心，不主动追「待确认建议」；到点未确认仍优先
    chase_suggestions = period in {"清晨", "上午", "下午", "傍晚"}
    if chase_suggestions:
        try:
            reminders = await reminder_svc.list_for_user(session, user=user)
        except Exception:
            logger.warning("opening_list_reminders_failed user_id=%s", user.id, exc_info=True)
            reminders = []
        for reminder in reminders:
            if reminder.status != ReminderStatus.PENDING_CONFIRM.value:
                continue
            title = (reminder.title or "").strip() or "提醒"
            who = (reminder.suggested_by_display_name or "").strip() or "家人"
            clock = reminder.schedule_time.strftime("%H:%M")
            items.append(f"子女新建议的提醒，等您确认：{who}想帮您设「{title}」（{clock}）")
            if len(items) >= _MAX_HIGHLIGHTS:
                return items

    try:
        family = await get_family(session, user)
    except Exception:
        logger.warning("opening_get_family_failed user_id=%s", user.id, exc_info=True)
        family = None
    if family is None:
        return items

    try:
        result = await session.execute(
            select(FamilyMessage)
            .where(
                FamilyMessage.family_id == family.id,
                FamilyMessage.kind == FamilyMessageKind.CHILD_STATUS.value,
                FamilyMessage.to_user_id == user.id,
                FamilyMessage.acknowledged_at.is_(None),
            )
            .order_by(FamilyMessage.created_at.desc())
            .limit(3)
        )
        messages = list(result.scalars().all())
    except Exception:
        logger.warning("opening_list_child_status_failed user_id=%s", user.id, exc_info=True)
        messages = []

    for msg in messages:
        text = (msg.delivered_text or msg.original_text or "").strip()
        if not text:
            continue
        if len(text) > 40:
            text = text[:40] + "…"
        items.append(f"子女报平安尚未回应：{text}")
        if len(items) >= _MAX_HIGHLIGHTS:
            break
    return items


async def load_opening_brief(
    session: AsyncSession,
    *,
    user: User,
    settings: Settings,
) -> OpeningBrief:
    """聚合开场简报；任何数据失败都返回可打招呼的兜底，不阻断建连。"""
    tz_name = settings.local_timezone
    try:
        now_local = _local_now(tz_name)
        period = classify_period(now_local.hour)
        visit_index, days_since_last = await _visit_stats(session, user=user, now_local=now_local)
        highlights = await _collect_highlights(
            session,
            user=user,
            settings=settings,
            tz_name=tz_name,
            period=period,
            visit_index=visit_index,
        )
        return OpeningBrief(
            period=period,
            visit_index=visit_index,
            days_since_last=days_since_last,
            highlights=highlights,
        )
    except Exception:
        logger.warning("load_opening_brief_failed user_id=%s", user.id, exc_info=True)
        now_local = _local_now(tz_name)
        return OpeningBrief(
            period=classify_period(now_local.hour),
            visit_index=1,
            days_since_last=0,
            highlights=[],
        )
