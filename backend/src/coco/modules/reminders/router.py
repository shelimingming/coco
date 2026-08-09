"""提醒路由。"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends

from coco.config import Settings, get_settings
from coco.deps import CurrentUserDep, SessionDep
from coco.modules.reminders.schemas import (
    DelayRequest,
    OccurrenceResponse,
    ReminderCreateRequest,
    ReminderResponse,
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


@router.post(
    "/{reminder_id}/occurrences/{occurrence_id}/confirm",
    response_model=None,
)
async def confirm_occurrence(
    reminder_id: UUID,
    occurrence_id: UUID,
    session: SessionDep,
    user: CurrentUserDep,
    service: ReminderService = Depends(get_reminder_service),
) -> OccurrenceResponse | dict:
    return await service.confirm_occurrence(
        session,
        user=user,
        reminder_id=reminder_id,
        occurrence_id=occurrence_id,
    )


@router.post(
    "/{reminder_id}/occurrences/{occurrence_id}/delay",
    response_model=OccurrenceResponse,
)
async def delay_occurrence(
    reminder_id: UUID,
    occurrence_id: UUID,
    body: DelayRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: ReminderService = Depends(get_reminder_service),
) -> OccurrenceResponse:
    return await service.delay_occurrence(
        session,
        user=user,
        reminder_id=reminder_id,
        occurrence_id=occurrence_id,
        body=body,
    )
