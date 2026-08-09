"""手机号登录路由。"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from coco.config import Settings, get_settings
from coco.deps import CurrentUserDep, PrincipalDep, SessionDep
from coco.modules.auth.schemas import (
    AuthSessionResponse,
    LogoutRequest,
    PhoneCodeRequest,
    PhoneCodeResponse,
    PhoneLoginRequest,
    RefreshRequest,
    UserResponse,
)
from coco.modules.auth.service import AuthService

router = APIRouter(prefix="/v1/auth", tags=["auth"])
me_router = APIRouter(prefix="/v1", tags=["auth"])


def get_auth_service(settings: Settings = Depends(get_settings)) -> AuthService:
    return AuthService(settings)


@router.post("/phone/code", response_model=PhoneCodeResponse)
async def request_phone_code(
    body: PhoneCodeRequest,
    session: SessionDep,
    service: AuthService = Depends(get_auth_service),
) -> PhoneCodeResponse:
    return await service.request_phone_code(session, phone=body.phone)


@router.post("/phone/login", response_model=AuthSessionResponse)
async def login_with_phone(
    body: PhoneLoginRequest,
    session: SessionDep,
    service: AuthService = Depends(get_auth_service),
) -> AuthSessionResponse:
    return await service.login_with_phone(
        session,
        challenge_id=body.challenge_id,
        phone=body.phone,
        code=body.code,
        role=body.role,
        display_name=body.display_name,
        device_id=body.device_id,
    )


@router.post("/refresh", response_model=AuthSessionResponse)
async def refresh_session(
    body: RefreshRequest,
    session: SessionDep,
    service: AuthService = Depends(get_auth_service),
) -> AuthSessionResponse:
    return await service.refresh_session(
        session,
        refresh_token=body.refresh_token,
        device_id=body.device_id,
    )


@router.post("/logout")
async def logout(
    body: LogoutRequest,
    session: SessionDep,
    principal: PrincipalDep,
    service: AuthService = Depends(get_auth_service),
) -> dict[str, bool]:
    await service.logout(
        session,
        user_id=principal.user_id,
        session_id=principal.session_id,
        refresh_token=body.refresh_token,
    )
    return {"ok": True}


@me_router.get("/me", response_model=UserResponse)
async def get_me(
    user: CurrentUserDep,
    service: AuthService = Depends(get_auth_service),
) -> UserResponse:
    return await service.get_me(user)
