"""通知路由。"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, Query

from coco.deps import CurrentUserDep, SessionDep
from coco.modules.notifications.schemas import NotificationResponse
from coco.modules.notifications.service import NotificationService

router = APIRouter(prefix="/v1/notifications", tags=["notifications"])


def get_notification_service() -> NotificationService:
    return NotificationService()


@router.get("", response_model=list[NotificationResponse])
async def list_notifications(
    session: SessionDep,
    user: CurrentUserDep,
    unread_only: bool = Query(default=False),
    service: NotificationService = Depends(get_notification_service),
) -> list[NotificationResponse]:
    return await service.list_for_user(session, user=user, unread_only=unread_only)


@router.post("/{notification_id}/read", response_model=NotificationResponse)
async def mark_notification_read(
    notification_id: UUID,
    session: SessionDep,
    user: CurrentUserDep,
    service: NotificationService = Depends(get_notification_service),
) -> NotificationResponse:
    return await service.mark_read(session, user=user, notification_id=notification_id)
