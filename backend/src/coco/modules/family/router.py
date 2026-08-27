"""家庭绑定路由。"""

from __future__ import annotations

from collections import defaultdict
from datetime import UTC, datetime, timedelta
from threading import Lock

from fastapi import APIRouter, Depends, Request, Response

from coco.config import Settings, get_settings
from coco.deps import CurrentUserDep, SessionDep
from coco.errors import AppError
from coco.modules.family.schemas import (
    FamilyInviteCreateResponse,
    FamilyInvitePreviewResponse,
    FamilyJoinRequest,
    FamilyResponse,
)
from coco.modules.family.service import FamilyService

router = APIRouter(prefix="/v1/family", tags=["family"])

# 预览接口免鉴权，按 IP 做小时窗口限流，避免穷举邀请码
_preview_hits: dict[str, list[datetime]] = defaultdict(list)
_preview_lock = Lock()


def get_family_service(settings: Settings = Depends(get_settings)) -> FamilyService:
    return FamilyService(settings)


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def _enforce_preview_rate_limit(ip: str, *, limit: int) -> None:
    now = datetime.now(UTC)
    window_start = now - timedelta(hours=1)
    with _preview_lock:
        hits = [ts for ts in _preview_hits[ip] if ts >= window_start]
        if len(hits) >= limit:
            raise AppError(429, "family.too_many_previews", "查看邀请过于频繁，请稍后再试。")
        hits.append(now)
        _preview_hits[ip] = hits


@router.post("/invite", response_model=FamilyInviteCreateResponse)
async def create_invite(
    session: SessionDep,
    user: CurrentUserDep,
    service: FamilyService = Depends(get_family_service),
) -> FamilyInviteCreateResponse:
    return await service.create_invite(session, user=user)


@router.get("/invites/{code}", response_model=FamilyInvitePreviewResponse)
async def preview_invite(
    code: str,
    request: Request,
    session: SessionDep,
    settings: Settings = Depends(get_settings),
    service: FamilyService = Depends(get_family_service),
) -> FamilyInvitePreviewResponse:
    _enforce_preview_rate_limit(ip=_client_ip(request), limit=settings.invite_preview_limit_per_hour)
    return await service.preview_invite(session, code=code)


@router.post("/join", response_model=FamilyResponse)
async def join_family(
    body: FamilyJoinRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: FamilyService = Depends(get_family_service),
) -> FamilyResponse:
    return await service.join_family(session, user=user, code=body.code)


@router.get("", response_model=FamilyResponse)
async def get_family(
    session: SessionDep,
    user: CurrentUserDep,
    service: FamilyService = Depends(get_family_service),
) -> FamilyResponse:
    return await service.get_family_view(session, user)


@router.post("/unbind", status_code=204)
async def unbind_family(
    session: SessionDep,
    user: CurrentUserDep,
    service: FamilyService = Depends(get_family_service),
) -> Response:
    await service.unbind_family(session, user=user)
    return Response(status_code=204)
