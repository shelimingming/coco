"""手机号登录业务逻辑。"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings
from coco.errors import AppError
from coco.models.auth import AuthSession, PhoneCode, PhoneCodePurpose
from coco.models.user import User, UserRole, UserStatus
from coco.modules.auth.schemas import (
    AuthSessionResponse,
    PhoneCodeResponse,
    UserResponse,
)
from coco.modules.auth.sms import SmsSender, build_sms_sender, resolve_login_code
from coco.security import (
    create_access_token,
    generate_refresh_token,
    mask_phone,
    normalize_mainland_phone,
    privacy_digest,
)


class AuthService:
    def __init__(self, settings: Settings, sms_sender: SmsSender | None = None) -> None:
        self._settings = settings
        self._sms = sms_sender or build_sms_sender(settings)

    async def request_phone_code(self, session: AsyncSession, *, phone: str) -> PhoneCodeResponse:
        normalized = normalize_mainland_phone(phone)
        phone_hash = privacy_digest(self._settings, "phone", normalized)

        # 开发短信不走真实通道；双端演示页会自动发码，小时限额会误伤本地联调
        if self._settings.sms_provider != "dev":
            one_hour_ago = datetime.now(UTC) - timedelta(hours=1)
            recent_count = await session.scalar(
                select(func.count())
                .select_from(PhoneCode)
                .where(
                    PhoneCode.phone_hash == phone_hash,
                    PhoneCode.created_at >= one_hour_ago,
                )
            )
            if int(recent_count or 0) >= self._settings.otp_request_limit_per_hour:
                raise AppError(429, "auth.too_many_codes", "验证码发送过于频繁，请稍后再试。")

        code = resolve_login_code(self._settings)
        challenge_id = uuid.uuid4()
        expires_at = datetime.now(UTC) + timedelta(seconds=self._settings.otp_ttl_seconds)
        code_hash = privacy_digest(self._settings, f"otp:{challenge_id}", code)

        challenge = PhoneCode(
            id=challenge_id,
            phone_hash=phone_hash,
            code_hash=code_hash,
            purpose=PhoneCodePurpose.LOGIN.value,
            attempts=0,
            expires_at=expires_at,
            created_at=datetime.now(UTC),
        )
        session.add(challenge)
        await self._sms.send_login_code(phone=normalized, code=code)
        await session.commit()

        existing = await session.scalar(select(User.id).where(User.phone_hash == phone_hash))
        return PhoneCodeResponse(
            challenge_id=challenge_id,
            expires_at=expires_at,
            is_registered=existing is not None,
            # 仅开发短信模式回传固定码，方便前端联调
            dev_code=code if self._settings.sms_provider == "dev" else None,
        )

    async def login_with_phone(
        self,
        session: AsyncSession,
        *,
        challenge_id: uuid.UUID,
        phone: str,
        code: str,
        role: UserRole,
        display_name: str | None,
        device_id: str,
    ) -> AuthSessionResponse:
        normalized = normalize_mainland_phone(phone)
        phone_hash = privacy_digest(self._settings, "phone", normalized)
        await self._consume_phone_code(
            session,
            challenge_id=challenge_id,
            phone_hash=phone_hash,
            code=code,
        )
        return await self._establish_session(
            session,
            phone_hash=phone_hash,
            phone_masked=mask_phone(normalized),
            phone_e164=normalized,
            role=role,
            display_name=display_name,
            device_id=device_id,
        )

    async def refresh_session(
        self,
        session: AsyncSession,
        *,
        refresh_token: str,
        device_id: str,
    ) -> AuthSessionResponse:
        token_hash = privacy_digest(self._settings, "refresh", refresh_token)
        result = await session.execute(
            select(AuthSession, User)
            .join(User, User.id == AuthSession.user_id)
            .where(AuthSession.refresh_token_hash == token_hash)
        )
        row = result.one_or_none()
        if row is None:
            raise AppError(401, "auth.invalid_token", "登录状态无效，请重新登录。")

        auth_session, user = row
        now = datetime.now(UTC)
        if auth_session.revoked_at is not None or auth_session.expires_at <= now:
            raise AppError(401, "auth.session_expired", "登录已过期，请重新登录。")
        if auth_session.device_id != device_id:
            raise AppError(401, "auth.invalid_token", "登录状态无效，请重新登录。")
        if user.status != UserStatus.ACTIVE.value:
            raise AppError(403, "auth.user_disabled", "账号不可用，请联系支持。")

        # refresh token 轮换：旧 hash 作废，签发新会话凭证
        new_refresh = generate_refresh_token()
        auth_session.refresh_token_hash = privacy_digest(self._settings, "refresh", new_refresh)
        auth_session.expires_at = now + timedelta(days=self._settings.refresh_token_ttl_days)
        auth_session.updated_at = now
        await session.commit()

        access_token, access_expires = create_access_token(
            self._settings,
            user_id=user.id,
            role=UserRole(user.role),
            session_id=auth_session.id,
        )
        return AuthSessionResponse(
            access_token=access_token,
            refresh_token=new_refresh,
            expires_at=access_expires,
            refresh_expires_at=auth_session.expires_at,
            user=self._to_user_response(user),
        )

    async def logout(
        self,
        session: AsyncSession,
        *,
        user_id: uuid.UUID,
        session_id: uuid.UUID,
        refresh_token: str | None,
    ) -> None:
        now = datetime.now(UTC)
        auth_session = await session.get(AuthSession, session_id)
        if auth_session is not None and auth_session.user_id == user_id:
            auth_session.revoked_at = now
            auth_session.updated_at = now

        if refresh_token:
            token_hash = privacy_digest(self._settings, "refresh", refresh_token)
            result = await session.execute(
                select(AuthSession).where(AuthSession.refresh_token_hash == token_hash)
            )
            other = result.scalar_one_or_none()
            if other is not None and other.user_id == user_id and other.revoked_at is None:
                other.revoked_at = now
                other.updated_at = now

        await session.commit()

    async def get_me(self, user: User) -> UserResponse:
        return self._to_user_response(user)

    async def _consume_phone_code(
        self,
        session: AsyncSession,
        *,
        challenge_id: uuid.UUID,
        phone_hash: str,
        code: str,
    ) -> None:
        challenge = await session.get(PhoneCode, challenge_id)
        if challenge is None or challenge.phone_hash != phone_hash:
            raise AppError(400, "auth.invalid_or_expired_code", "验证码不正确或已过期。")
        if challenge.purpose != PhoneCodePurpose.LOGIN.value:
            raise AppError(400, "auth.invalid_or_expired_code", "验证码不正确或已过期。")
        if challenge.consumed_at is not None:
            raise AppError(400, "auth.invalid_or_expired_code", "验证码已使用，请重新获取。")
        if challenge.expires_at <= datetime.now(UTC):
            raise AppError(400, "auth.invalid_or_expired_code", "验证码不正确或已过期。")
        if challenge.attempts >= self._settings.otp_max_attempts:
            raise AppError(429, "auth.too_many_attempts", "尝试次数过多，请重新获取验证码。")

        expected = privacy_digest(self._settings, f"otp:{challenge_id}", code)
        if not secrets_compare(expected, challenge.code_hash):
            challenge.attempts += 1
            await session.commit()
            raise AppError(400, "auth.invalid_or_expired_code", "验证码不正确或已过期。")

        challenge.consumed_at = datetime.now(UTC)
        await session.flush()

    async def _establish_session(
        self,
        session: AsyncSession,
        *,
        phone_hash: str,
        phone_masked: str,
        phone_e164: str,
        role: UserRole,
        display_name: str | None,
        device_id: str,
    ) -> AuthSessionResponse:
        user = await session.scalar(select(User).where(User.phone_hash == phone_hash))
        if user is None:
            name = (display_name or "").strip() or default_display_name(role)
            user = User(
                phone_hash=phone_hash,
                phone_masked=phone_masked,
                phone_e164=phone_e164,
                display_name=name,
                role=role.value,
                status=UserStatus.ACTIVE.value,
            )
            session.add(user)
            await session.flush()
        else:
            if user.status != UserStatus.ACTIVE.value:
                raise AppError(403, "auth.user_disabled", "账号不可用，请联系支持。")
            # 已注册用户允许本次登录切换当前角色（家庭绑定后续再约束）
            user.role = role.value
            if display_name and display_name.strip():
                user.display_name = display_name.strip()
            user.phone_masked = phone_masked
            # 存量账号补齐明文，供子女端拨打
            user.phone_e164 = phone_e164

        now = datetime.now(UTC)
        refresh_token = generate_refresh_token()
        auth_session = AuthSession(
            user_id=user.id,
            refresh_token_hash=privacy_digest(self._settings, "refresh", refresh_token),
            device_id=device_id,
            expires_at=now + timedelta(days=self._settings.refresh_token_ttl_days),
        )
        session.add(auth_session)
        await session.commit()
        await session.refresh(user)
        await session.refresh(auth_session)

        access_token, access_expires = create_access_token(
            self._settings,
            user_id=user.id,
            role=UserRole(user.role),
            session_id=auth_session.id,
        )
        return AuthSessionResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_at=access_expires,
            refresh_expires_at=auth_session.expires_at,
            user=self._to_user_response(user),
        )

    @staticmethod
    def _to_user_response(user: User) -> UserResponse:
        return UserResponse(
            id=user.id,
            display_name=user.display_name,
            role=UserRole(user.role),
            phone_masked=user.phone_masked,
            status=user.status,
        )


def default_display_name(role: UserRole) -> str:
    return "家人" if role == UserRole.PARENT else "孩子"


def secrets_compare(left: str, right: str) -> bool:
    import hmac

    return hmac.compare_digest(left, right)
