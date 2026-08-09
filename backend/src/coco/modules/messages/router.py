"""子女报平安路由。"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from coco.config import Settings, get_settings
from coco.deps import CurrentUserDep, SessionDep
from coco.modules.messages.schemas import (
    FamilyMessageResponse,
    MessagePreviewRequest,
    MessagePreviewResponse,
    MessageSendRequest,
)
from coco.modules.messages.service import MessageService

router = APIRouter(prefix="/v1/messages", tags=["messages"])


def get_message_service(settings: Settings = Depends(get_settings)) -> MessageService:
    return MessageService(settings)


@router.post("/preview", response_model=MessagePreviewResponse)
async def preview_message(
    body: MessagePreviewRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: MessageService = Depends(get_message_service),
) -> MessagePreviewResponse:
    return await service.preview(session, user=user, text=body.text)


@router.post("", response_model=FamilyMessageResponse)
async def send_message(
    body: MessageSendRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: MessageService = Depends(get_message_service),
) -> FamilyMessageResponse:
    return await service.send(session, user=user, body=body)


@router.get("", response_model=list[FamilyMessageResponse])
async def list_messages(
    session: SessionDep,
    user: CurrentUserDep,
    service: MessageService = Depends(get_message_service),
) -> list[FamilyMessageResponse]:
    return await service.list_for_user(session, user=user)
