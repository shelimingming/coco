"""FastAPI 依赖：数据库会话与当前用户。"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings, get_settings
from coco.database import get_session
from coco.errors import AppError
from coco.models.auth import AuthSession
from coco.models.user import User, UserStatus
from coco.security import Principal, decode_access_token

SessionDep = Annotated[AsyncSession, Depends(get_session)]
SettingsDep = Annotated[Settings, Depends(get_settings)]

_bearer = HTTPBearer(auto_error=False)


async def get_current_principal(
    settings: SettingsDep,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> Principal:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise AppError(401, "auth.missing_token", "请先登录。")
    return decode_access_token(settings, credentials.credentials)


async def get_current_user(
    session: SessionDep,
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> User:
    # 同时校验会话未吊销，避免仅靠 JWT 过期时间
    result = await session.execute(
        select(User, AuthSession)
        .join(AuthSession, AuthSession.user_id == User.id)
        .where(
            User.id == principal.user_id,
            AuthSession.id == principal.session_id,
        )
    )
    row = result.one_or_none()
    if row is None:
        raise AppError(401, "auth.invalid_token", "登录状态无效，请重新登录。")

    user, auth_session = row
    if auth_session.revoked_at is not None:
        raise AppError(401, "auth.session_expired", "登录已失效，请重新登录。")

    expires = auth_session.expires_at
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=UTC)
    if expires <= datetime.now(UTC):
        raise AppError(401, "auth.session_expired", "登录已过期，请重新登录。")
    if user.status != UserStatus.ACTIVE.value:
        raise AppError(403, "auth.user_disabled", "账号不可用，请联系支持。")
    return user


CurrentUserDep = Annotated[User, Depends(get_current_user)]
PrincipalDep = Annotated[Principal, Depends(get_current_principal)]
