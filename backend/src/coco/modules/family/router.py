"""家庭绑定路由。"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from coco.config import Settings, get_settings
from coco.deps import CurrentUserDep, SessionDep
from coco.modules.family.schemas import (
    FamilyInviteCreateResponse,
    FamilyInvitePreviewResponse,
    FamilyJoinRequest,
    FamilyResponse,
)
from coco.modules.family.service import FamilyService

router = APIRouter(prefix="/v1/family", tags=["family"])


def get_family_service(settings: Settings = Depends(get_settings)) -> FamilyService:
    return FamilyService(settings)


@router.post("/invite", response_model=FamilyInviteCreateResponse)
async def create_invite(
    session: SessionDep,
    user: CurrentUserDep,
    service: FamilyService = Depends(get_family_service),
) -> FamilyInviteCreateResponse:
    return await service.create_invite(session, user=user)


@router.get("/invite/{token}", response_model=FamilyInvitePreviewResponse)
async def preview_invite(
    token: str,
    session: SessionDep,
    service: FamilyService = Depends(get_family_service),
) -> FamilyInvitePreviewResponse:
    """免鉴权：被邀请方打开链接前预览邀请信息。"""
    return await service.preview_invite(session, token=token)


@router.post("/join", response_model=FamilyResponse)
async def join_family(
    body: FamilyJoinRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: FamilyService = Depends(get_family_service),
) -> FamilyResponse:
    return await service.join_family(session, user=user, token=body.token)


@router.get("", response_model=FamilyResponse)
async def get_family(
    session: SessionDep,
    user: CurrentUserDep,
    service: FamilyService = Depends(get_family_service),
) -> FamilyResponse:
    return await service.get_family_view(session, user)
