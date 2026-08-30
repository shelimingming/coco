"""每日小记路由。"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Body, Depends, File, UploadFile

from coco.config import Settings, get_settings
from coco.deps import CurrentUserDep, SessionDep
from coco.models.daily_note import DailyNoteSource
from coco.modules.daily_notes.schemas import (
    DailyNoteGenerateRequest,
    DailyNoteListResponse,
    DailyNoteResponse,
    DailyNoteSettingsResponse,
    DailyNoteSettingsUpdateRequest,
)
from coco.modules.daily_notes.service import DailyNoteService

router = APIRouter(prefix="/v1", tags=["daily-notes"])


def get_daily_note_service(settings: Settings = Depends(get_settings)) -> DailyNoteService:
    return DailyNoteService(settings)


@router.get("/daily-notes/settings", response_model=DailyNoteSettingsResponse)
async def get_daily_note_settings(
    session: SessionDep,
    user: CurrentUserDep,
    service: DailyNoteService = Depends(get_daily_note_service),
) -> DailyNoteSettingsResponse:
    return await service.get_settings(session, user=user)


@router.patch("/daily-notes/settings", response_model=DailyNoteSettingsResponse)
async def patch_daily_note_settings(
    body: DailyNoteSettingsUpdateRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: DailyNoteService = Depends(get_daily_note_service),
) -> DailyNoteSettingsResponse:
    return await service.update_settings(session, user=user, body=body)


@router.post("/daily-notes/settings/parent-photo", response_model=DailyNoteSettingsResponse)
async def upload_parent_photo(
    session: SessionDep,
    user: CurrentUserDep,
    image: UploadFile = File(..., description="老人参考照"),
    service: DailyNoteService = Depends(get_daily_note_service),
) -> DailyNoteSettingsResponse:
    data = await image.read()
    mime = image.content_type or "image/jpeg"
    return await service.upload_parent_photo(session, user=user, data=data, mime_type=mime)


@router.delete("/daily-notes/settings/parent-photo", response_model=DailyNoteSettingsResponse)
async def delete_parent_photo(
    session: SessionDep,
    user: CurrentUserDep,
    service: DailyNoteService = Depends(get_daily_note_service),
) -> DailyNoteSettingsResponse:
    return await service.delete_parent_photo(session, user=user)


@router.get("/daily-notes", response_model=DailyNoteListResponse)
async def list_daily_notes(
    session: SessionDep,
    user: CurrentUserDep,
    service: DailyNoteService = Depends(get_daily_note_service),
) -> DailyNoteListResponse:
    items = await service.list_for_parent(session, user=user)
    return DailyNoteListResponse(items=items)


@router.post("/daily-notes/generate", response_model=DailyNoteResponse)
async def generate_daily_note(
    session: SessionDep,
    user: CurrentUserDep,
    body: DailyNoteGenerateRequest = Body(default_factory=DailyNoteGenerateRequest),
    service: DailyNoteService = Depends(get_daily_note_service),
) -> DailyNoteResponse:
    # 手动生成：立刻返回 pending，后台跑提取/撰写/配图；不受自动生成开关限制
    return await service.enqueue_generate_for_parent(
        session,
        user=user,
        source=DailyNoteSource.MANUAL.value,
        note_date=body.note_date,
        respect_generate_enabled=False,
    )


@router.get("/child/daily-notes/today", response_model=None)
async def child_daily_note_today(
    session: SessionDep,
    user: CurrentUserDep,
    service: DailyNoteService = Depends(get_daily_note_service),
) -> DailyNoteResponse | None:
    return await service.child_today(session, user=user)


@router.get("/daily-notes/{note_id}", response_model=DailyNoteResponse)
async def get_daily_note(
    note_id: UUID,
    session: SessionDep,
    user: CurrentUserDep,
    service: DailyNoteService = Depends(get_daily_note_service),
) -> DailyNoteResponse:
    return await service.get_for_parent(session, user=user, note_id=note_id)
