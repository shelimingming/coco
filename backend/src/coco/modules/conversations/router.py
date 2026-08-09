"""对话历史路由：仅父母可查，暂不提供删除。"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends

from coco.deps import CurrentUserDep, SessionDep
from coco.modules.conversations.schemas import ConversationDetailResponse, ConversationListItem
from coco.modules.conversations.service import ConversationService

router = APIRouter(prefix="/v1/conversations", tags=["conversations"])


def get_conversation_service() -> ConversationService:
    return ConversationService()


@router.get("", response_model=list[ConversationListItem])
async def list_conversations(
    session: SessionDep,
    user: CurrentUserDep,
    service: ConversationService = Depends(get_conversation_service),
) -> list[ConversationListItem]:
    return await service.list_for_user(session, user=user)


@router.get("/{conversation_id}", response_model=ConversationDetailResponse)
async def get_conversation(
    conversation_id: UUID,
    session: SessionDep,
    user: CurrentUserDep,
    service: ConversationService = Depends(get_conversation_service),
) -> ConversationDetailResponse:
    return await service.get_for_user(session, user=user, conversation_id=conversation_id)
