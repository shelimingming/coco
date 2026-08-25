"""提醒路由。"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends

from coco.config import Settings, get_settings
from coco.deps import CurrentUserDep, SessionDep
from coco.modules.reminders.schemas import (
    OccurrenceRespondRequest,
    OccurrenceResponse,
    ReminderCreateRequest,
    ReminderResponse,
    ReminderSuggestionCreateRequest,
    ReminderUpdateRequest,
)
from coco.modules.reminders.service import ReminderService

router = APIRouter(prefix="/v1/reminders", tags=["reminders"])


def get_reminder_service(settings: Settings = Depends(get_settings)) -> ReminderService:
    return ReminderService(settings)


@router.post("", response_model=None)
async def create_reminder(
    body: ReminderCreateRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: ReminderService = Depends(get_reminder_service),
) -> ReminderResponse | dict:
    return await service.create(session, user=user, body=body)


@router.get("", response_model=list[ReminderResponse])
async def list_reminders(
    session: SessionDep,
    user: CurrentUserDep,
    service: ReminderService = Depends(get_reminder_service),
) -> list[ReminderResponse]:
    return await service.list_for_user(session, user=user)


@router.post("/suggestions", response_model=ReminderResponse)
async def create_reminder_suggestion(
    body: ReminderSuggestionCreateRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: ReminderService = Depends(get_reminder_service),
) -> ReminderResponse:
    return await service.create_suggestion(session, user=user, body=body)


@router.get("/suggestions", response_model=list[ReminderResponse])
async def list_reminder_suggestions(
    session: SessionDep,
    user: CurrentUserDep,
    service: ReminderService = Depends(get_reminder_service),
) -> list[ReminderResponse]:
    return await service.list_suggestions_for_child(session, user=user)


@router.post("/{reminder_id}/accept", response_model=ReminderResponse)
async def accept_reminder_suggestion(
    reminder_id: UUID,
    session: SessionDep,
    user: CurrentUserDep,
    service: ReminderService = Depends(get_reminder_service),
) -> ReminderResponse:
    return await service.accept_suggestion(session, user=user, reminder_id=reminder_id)


@router.post("/{reminder_id}/reject", response_model=ReminderResponse)
async def reject_reminder_suggestion(
    reminder_id: UUID,
    session: SessionDep,
    user: CurrentUserDep,
    service: ReminderService = Depends(get_reminder_service),
) -> ReminderResponse:
    return await service.reject_suggestion(session, user=user, reminder_id=reminder_id)


@router.patch("/{reminder_id}", response_model=ReminderResponse)
async def update_reminder(
    reminder_id: UUID,
    body: ReminderUpdateRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: ReminderService = Depends(get_reminder_service),
) -> ReminderResponse:
    return await service.update(session, user=user, reminder_id=reminder_id, body=body)


@router.delete("/{reminder_id}")
async def delete_reminder(
    reminder_id: UUID,
    session: SessionDep,
    user: CurrentUserDep,
    service: ReminderService = Depends(get_reminder_service),
) -> dict[str, bool]:
    return await service.delete(session, user=user, reminder_id=reminder_id)


@router.post("/occurrences/{occurrence_id}/response", response_model=None)
async def respond_to_occurrence(
    occurrence_id: UUID,
    body: OccurrenceRespondRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: ReminderService = Depends(get_reminder_service),
) -> OccurrenceResponse | dict:
    return await service.respond_to_occurrence(
        session,
        user=user,
        occurrence_id=occurrence_id,
        body=body,
    )
