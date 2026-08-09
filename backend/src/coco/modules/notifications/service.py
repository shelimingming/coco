"""应用内通知：列表与标记已读。"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.errors import AppError
from coco.models.notification import Notification
from coco.models.user import User
from coco.modules.notifications.schemas import NotificationResponse


def _to_response(n: Notification) -> NotificationResponse:
    return NotificationResponse(
        id=n.id,
        type=n.type,
        title=n.title,
        body=n.body,
        payload=n.payload or {},
        read_at=n.read_at,
        created_at=n.created_at,
    )


class NotificationService:
    async def list_for_user(
        self,
        session: AsyncSession,
        *,
        user: User,
        unread_only: bool = False,
        limit: int = 50,
    ) -> list[NotificationResponse]:
        query = (
            select(Notification)
            .where(Notification.user_id == user.id)
            .order_by(Notification.created_at.desc())
            .limit(min(limit, 100))
        )
        if unread_only:
            query = query.where(Notification.read_at.is_(None))
        result = await session.execute(query)
        return [_to_response(n) for n in result.scalars().all()]

    async def mark_read(
        self, session: AsyncSession, *, user: User, notification_id: UUID
    ) -> NotificationResponse:
        n = await session.get(Notification, notification_id)
        if n is None or n.user_id != user.id:
            raise AppError(404, "notification.not_found", "找不到这条通知。")
        if n.read_at is None:
            n.read_at = datetime.now(UTC)
            await session.commit()
            await session.refresh(n)
        return _to_response(n)
