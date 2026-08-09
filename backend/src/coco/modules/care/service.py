"""关怀摘要与子女今日状态（纯规则聚合，不过模型）。"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings
from coco.errors import AppError
from coco.models.care import CareShare, CareSource
from coco.models.family import FamilyStatus
from coco.models.notification import Notification, NotificationType
from coco.models.reminder import OccurrenceState, Reminder, ReminderOccurrence
from coco.models.user import User, UserRole
from coco.modules.care.schemas import (
    CareShareCreateRequest,
    CareShareResponse,
    ChildTodayReminderItem,
    ChildTodayResponse,
)
from coco.modules.family.service import require_family


def _to_response(share: CareShare) -> CareShareResponse:
    return CareShareResponse(
        id=share.id,
        parent_id=share.parent_id,
        child_id=share.child_id,
        summary=share.summary,
        urgency=share.urgency,
        reply_expectation=share.reply_expectation,
        source=share.source,
        parent_confirmed=share.parent_confirmed,
        read_at=share.read_at,
        created_at=share.created_at,
    )


def compute_child_today_status(
    *,
    has_escalated: bool,
    has_attention_share: bool,
) -> str:
    """子女首页三级状态：规则优先，禁止医疗推断。"""
    if has_escalated:
        return "NEED_CONTACT"
    if has_attention_share:
        return "ATTENTION"
    return "NORMAL"


class CareService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    async def create_share(
        self,
        session: AsyncSession,
        *,
        user: User,
        body: CareShareCreateRequest,
        source: str = CareSource.PARENT_CONVERSATION.value,
    ) -> CareShareResponse | dict:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "care.parent_required", "只有老人模式可以分享给子女。")
        if not body.user_confirmed:
            return {
                "status": "need_confirmation",
                "summary": body.summary.strip(),
                "urgency": body.urgency,
            }

        family = await require_family(session, user)
        if family.child_user_id is None or family.status != FamilyStatus.ACTIVE.value:
            raise AppError(
                400,
                "care.no_child",
                "还没有绑定子女，无法分享。请先让子女用邀请码加入家庭。",
            )

        share = CareShare(
            parent_id=user.id,
            child_id=family.child_user_id,
            summary=body.summary.strip(),
            urgency=body.urgency,
            reply_expectation=body.reply_expectation,
            source=source,
            parent_confirmed=True,
        )
        session.add(share)
        # 同步写入子女通知，客户端拉取
        session.add(
            Notification(
                user_id=family.child_user_id,
                type=NotificationType.CARE_MESSAGE.value,
                title="家人分享了一条消息",
                body=share.summary,
                payload={"care_share_id": str(share.id)},
            )
        )
        await session.commit()
        await session.refresh(share)
        return _to_response(share)

    async def list_for_child(
        self, session: AsyncSession, *, user: User, unread_only: bool = False
    ) -> list[CareShareResponse]:
        if user.role != UserRole.CHILD.value:
            raise AppError(403, "care.child_required", "只有子女模式可以查看关怀摘要。")
        query = (
            select(CareShare)
            .where(
                CareShare.child_id == user.id,
                CareShare.parent_confirmed.is_(True),
            )
            .order_by(CareShare.created_at.desc())
        )
        if unread_only:
            query = query.where(CareShare.read_at.is_(None))
        result = await session.execute(query)
        return [_to_response(s) for s in result.scalars().all()]

    async def mark_read(
        self, session: AsyncSession, *, user: User, share_id: UUID
    ) -> CareShareResponse:
        """子女按条确认「知道了」；幂等，已读不再改时间。"""
        if user.role != UserRole.CHILD.value:
            raise AppError(403, "care.child_required", "只有子女模式可以标记关怀摘要已读。")
        share = await session.get(CareShare, share_id)
        if share is None or share.child_id != user.id or not share.parent_confirmed:
            raise AppError(404, "care.not_found", "找不到这条需要关注的内容。")
        if share.read_at is None:
            share.read_at = datetime.now(UTC)
            await session.commit()
            await session.refresh(share)
        return _to_response(share)

    async def child_today(self, session: AsyncSession, *, user: User) -> ChildTodayResponse:
        if user.role != UserRole.CHILD.value:
            raise AppError(403, "care.child_required", "只有子女模式可以查看今日状态。")

        family = await require_family(session, user)
        if family.child_user_id != user.id:
            raise AppError(403, "care.not_member", "您不是这个家庭的子女成员。")

        tz = ZoneInfo(self._settings.local_timezone)
        datetime.now(UTC)
        local_start = datetime.now(tz).replace(hour=0, minute=0, second=0, microsecond=0)
        day_start = local_start.astimezone(UTC)
        day_end = day_start + timedelta(days=1)

        # 首页只展示今日未读分享；点「知道了」后不再出现
        shares_result = await session.execute(
            select(CareShare)
            .where(
                CareShare.child_id == user.id,
                CareShare.parent_confirmed.is_(True),
                CareShare.read_at.is_(None),
                CareShare.created_at >= day_start,
                CareShare.created_at < day_end,
            )
            .order_by(CareShare.created_at.desc())
        )
        shares = list(shares_result.scalars().all())

        # 今日未确认 / 已升级的提醒（措辞禁止写成「没有吃药」）
        occ_result = await session.execute(
            select(ReminderOccurrence, Reminder)
            .join(Reminder, Reminder.id == ReminderOccurrence.reminder_id)
            .where(
                Reminder.user_id == family.parent_user_id,
                ReminderOccurrence.due_at >= day_start,
                ReminderOccurrence.due_at < day_end,
                ReminderOccurrence.state.in_(
                    [
                        OccurrenceState.FIRST_REMINDER.value,
                        OccurrenceState.SECOND_REMINDER.value,
                        OccurrenceState.ESCALATED.value,
                    ]
                ),
            )
            .order_by(ReminderOccurrence.due_at.desc())
        )
        reminder_items: list[ChildTodayReminderItem] = []
        has_escalated = False
        for occ, reminder in occ_result.all():
            if occ.state == OccurrenceState.ESCALATED.value:
                has_escalated = True
            reminder_items.append(
                ChildTodayReminderItem(
                    title=reminder.title,
                    state=occ.state,
                    due_at=occ.due_at,
                )
            )

        has_attention = len(shares) > 0
        status = compute_child_today_status(
            has_escalated=has_escalated,
            has_attention_share=has_attention,
        )

        if status == "NEED_CONTACT":
            headline = "建议联系父母"
            reason = (
                "今天有提醒经过两次提示后仍未收到确认，建议电话联系。"
                "系统只能知道没有收到确认，不能判断是否已完成。"
            )
        elif status == "ATTENTION":
            headline = "有事情需要您关注"
            reason = None
        else:
            headline = "今天总体正常"
            reason = None
            if not reminder_items:
                headline = "今天总体正常，没有明确异常。"

        return ChildTodayResponse(
            status=status,
            headline=headline,
            attention_items=[_to_response(s) for s in shares],
            reminder_items=reminder_items,
            needs_contact_reason=reason,
        )
