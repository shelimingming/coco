"""手机号规范化、HMAC 摘要、JWT 签发与校验。"""

from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import jwt

from coco.config import Settings
from coco.errors import AppError
from coco.models.user import UserRole

_PHONE_DIGITS = re.compile(r"\D+")


def normalize_mainland_phone(value: str) -> str:
    """将输入规范为 +86 开头的大陆手机号。"""
    digits = _PHONE_DIGITS.sub("", value.strip())
    if digits.startswith("86") and len(digits) == 13:
        digits = digits[2:]
    if len(digits) != 11 or not digits.startswith("1"):
        raise AppError(422, "auth.invalid_phone", "请输入正确的大陆手机号。")
    return f"+86{digits}"


def mask_phone(normalized: str) -> str:
    """生成展示用掩码，如 138****8000。"""
    national = normalized.removeprefix("+86")
    return f"{national[:3]}****{national[-4:]}"


def privacy_digest(settings: Settings, purpose: str, value: str) -> str:
    """HMAC-SHA256 摘要，用于手机号 / OTP / refresh token。"""
    pepper = settings.auth_hash_pepper.get_secret_value().encode("utf-8")
    message = f"{purpose}:{value}".encode()
    return hmac.new(pepper, message, hashlib.sha256).hexdigest()


def generate_refresh_token() -> str:
    return secrets.token_urlsafe(48)


@dataclass(frozen=True, slots=True)
class Principal:
    user_id: uuid.UUID
    role: UserRole
    session_id: uuid.UUID
    token_id: str


def create_access_token(
    settings: Settings,
    *,
    user_id: uuid.UUID,
    role: UserRole,
    session_id: uuid.UUID,
) -> tuple[str, datetime]:
    now = datetime.now(UTC)
    expires_at = now + timedelta(seconds=settings.access_token_ttl_seconds)
    payload = {
        "sub": str(user_id),
        "role": role.value,
        "sid": str(session_id),
        "jti": str(uuid.uuid4()),
        "iat": int(now.timestamp()),
        "exp": int(expires_at.timestamp()),
        "iss": settings.auth_issuer,
        "aud": settings.auth_audience,
    }
    token = jwt.encode(
        payload,
        settings.auth_signing_key.get_secret_value(),
        algorithm="HS256",
    )
    return token, expires_at


def decode_access_token(settings: Settings, token: str) -> Principal:
    try:
        payload = jwt.decode(
            token,
            settings.auth_signing_key.get_secret_value(),
            algorithms=["HS256"],
            audience=settings.auth_audience,
            issuer=settings.auth_issuer,
        )
    except jwt.ExpiredSignatureError as exc:
        raise AppError(401, "auth.session_expired", "登录已过期，请重新登录。") from exc
    except jwt.PyJWTError as exc:
        raise AppError(401, "auth.invalid_token", "登录状态无效，请重新登录。") from exc

    try:
        role = UserRole(str(payload["role"]))
        return Principal(
            user_id=uuid.UUID(str(payload["sub"])),
            role=role,
            session_id=uuid.UUID(str(payload["sid"])),
            token_id=str(payload["jti"]),
        )
    except (KeyError, ValueError, TypeError) as exc:
        raise AppError(401, "auth.invalid_token", "登录状态无效，请重新登录。") from exc
