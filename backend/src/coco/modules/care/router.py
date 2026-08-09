"""关怀摘要与子女今日状态路由。"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, Query

from coco.config import Settings, get_settings
from coco.deps import CurrentUserDep, SessionDep
from coco.modules.care.schemas import (
    CareShareCreateRequest,
    CareShareResponse,
    ChildTodayResponse,
)
from coco.modules.care.service import CareService

router = APIRouter(prefix="/v1", tags=["care"])


def get_care_service(settings: Settings = Depends(get_settings)) -> CareService:
    return CareService(settings)


@router.post("/care-shares", response_model=None)
async def create_care_share(
    body: CareShareCreateRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: CareService = Depends(get_care_service),
) -> CareShareResponse | dict:
    return await service.create_share(session, user=user, body=body)


@router.get("/care-shares", response_model=list[CareShareResponse])
async def list_care_shares(
    session: SessionDep,
    user: CurrentUserDep,
    unread_only: bool = Query(default=False),
    service: CareService = Depends(get_care_service),
) -> list[CareShareResponse]:
    return await service.list_for_child(session, user=user, unread_only=unread_only)


@router.post("/care-shares/{share_id}/read", response_model=CareShareResponse)
async def mark_care_share_read(
    share_id: UUID,
    session: SessionDep,
    user: CurrentUserDep,
    service: CareService = Depends(get_care_service),
) -> CareShareResponse:
    return await service.mark_read(session, user=user, share_id=share_id)


@router.get("/child/today", response_model=ChildTodayResponse)
async def child_today(
    session: SessionDep,
    user: CurrentUserDep,
    service: CareService = Depends(get_care_service),
) -> ChildTodayResponse:
    return await service.child_today(session, user=user)
