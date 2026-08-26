"""家庭绑定业务：双向邀请链接 + 1 父母 / 1 子女。"""

from __future__ import annotations

import secrets
from datetime import UTC, datetime

from sqlalchemy import delete, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings
from coco.errors import AppError
from coco.models.family import Family, FamilyInvite, FamilyStatus
from coco.models.user import User, UserRole
from coco.modules.family.schemas import (
    FamilyInviteCreateResponse,
    FamilyInvitePreviewResponse,
    FamilyResponse,
)


async def get_family(session: AsyncSession, user: User) -> Family | None:
    """按当前用户查找所属家庭（父母或子女侧）。"""
    result = await session.execute(
        select(Family).where(
            or_(
                Family.parent_user_id == user.id,
                Family.child_user_id == user.id,
            )
        )
    )
    return result.scalar_one_or_none()


async def require_family(session: AsyncSession, user: User) -> Family:
    family = await get_family(session, user)
    if family is None:
        raise AppError(404, "family.not_found", "还没有绑定家庭。请先完成父母与子女的绑定。")
    return family


async def assert_login_role_allowed(
    session: AsyncSession,
    *,
    user: User,
    requested_role: UserRole,
) -> None:
    """已在家庭中的用户不能借登录切换角色，避免链接邀请绑定时角色被覆盖。"""
    family = await get_family(session, user)
    if family is None:
        return
    if family.parent_user_id == user.id and requested_role != UserRole.PARENT:
        raise AppError(
            409,
            "auth.role_locked",
            "您的账号已作为长辈加入家庭，请用长辈身份登录。",
        )
    if family.child_user_id == user.id and requested_role != UserRole.CHILD:
        raise AppError(
            409,
            "auth.role_locked",
            "您的账号已作为子女加入家庭，请用子女身份登录。",
        )


class FamilyService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def _build_invite_url(self, token: str) -> str:
        base = (self._settings.public_base_url or "").strip().rstrip("/")
        path = f"/invite/{token}"
        return f"{base}{path}" if base else path

    @staticmethod
    def _target_role_for_family(family: Family) -> UserRole:
        if family.child_user_id is None and family.parent_user_id is not None:
            return UserRole.CHILD
        if family.parent_user_id is None and family.child_user_id is not None:
            return UserRole.PARENT
        raise AppError(409, "family.already_bound", "该家庭已经完成绑定。")

    async def create_invite(
        self, session: AsyncSession, *, user: User
    ) -> FamilyInviteCreateResponse:
        if user.role == UserRole.PARENT.value:
            family = await session.scalar(select(Family).where(Family.parent_user_id == user.id))
            if family is None:
                family = Family(
                    parent_user_id=user.id,
                    child_user_id=None,
                    status=FamilyStatus.PENDING.value,
                )
                session.add(family)
                await session.flush()
            elif family.child_user_id is not None:
                raise AppError(
                    409,
                    "family.already_bound",
                    "已经绑定了子女，不能再生成邀请。如需更换请先解除绑定（MVP 暂不支持）。",
                )
        elif user.role == UserRole.CHILD.value:
            family = await session.scalar(select(Family).where(Family.child_user_id == user.id))
            if family is None:
                family = Family(
                    parent_user_id=None,
                    child_user_id=user.id,
                    status=FamilyStatus.PENDING.value,
                )
                session.add(family)
                await session.flush()
            elif family.parent_user_id is not None:
                raise AppError(
                    409,
                    "family.already_bound",
                    "已经绑定了父母，不能再生成邀请。如需更换请先解除绑定（MVP 暂不支持）。",
                )
        else:
            raise AppError(403, "family.role_required", "当前角色无法生成邀请。")

        now = datetime.now(UTC)
        token = secrets.token_urlsafe(22)
        invite = FamilyInvite(
            token=token,
            inviter_user_id=user.id,
            family_id=family.id,
            created_at=now,
        )
        session.add(invite)
        await session.commit()
        await session.refresh(invite)
        return FamilyInviteCreateResponse(
            token=invite.token,
            invite_url=self._build_invite_url(invite.token),
            family_id=family.id,
        )

    async def preview_invite(
        self, session: AsyncSession, *, token: str
    ) -> FamilyInvitePreviewResponse:
        normalized = token.strip()
        result = await session.execute(
            select(FamilyInvite, Family, User)
            .join(Family, Family.id == FamilyInvite.family_id)
            .join(User, User.id == FamilyInvite.inviter_user_id)
            .where(FamilyInvite.token == normalized)
            .order_by(FamilyInvite.created_at.desc())
        )
        row = result.first()
        if row is None:
            raise AppError(
                404,
                "family.invalid_invite",
                "邀请链接无效。请向家人重新索取，刚才没有建立任何家庭关系。",
            )
        invite, family, inviter = row
        if invite.consumed_at is not None:
            raise AppError(
                400,
                "family.invalid_invite",
                "邀请链接已被使用。请向家人重新索取，刚才没有建立任何家庭关系。",
            )
        target_role = self._target_role_for_family(family)
        return FamilyInvitePreviewResponse(
            inviter_display_name=inviter.display_name,
            target_role=target_role,
            valid=True,
        )

    async def _abandon_pending_family(self, session: AsyncSession, family: Family) -> None:
        """加入对方家庭前，放弃自己未完成的 pending 家庭及未消费邀请。"""
        await session.execute(delete(FamilyInvite).where(FamilyInvite.family_id == family.id))
        await session.delete(family)
        await session.flush()

    async def _resolve_invite(
        self,
        session: AsyncSession,
        *,
        token: str,
    ) -> tuple[FamilyInvite, Family]:
        normalized = token.strip()
        result = await session.execute(
            select(FamilyInvite, Family)
            .join(Family, Family.id == FamilyInvite.family_id)
            .where(
                FamilyInvite.token == normalized,
                FamilyInvite.consumed_at.is_(None),
            )
            .order_by(FamilyInvite.created_at.desc())
        )
        row = result.first()
        if row is None:
            raise AppError(
                400,
                "family.invalid_invite",
                "邀请无效或已被使用。请向家人重新索取，刚才没有建立任何家庭关系。",
            )
        return row

    async def join_family(
        self,
        session: AsyncSession,
        *,
        user: User,
        token: str,
    ) -> FamilyResponse:
        existing = await get_family(session, user)
        if existing is not None:
            # 已 active：禁止重复绑定；仅 pending 时可放弃后加入对方
            if existing.status == FamilyStatus.ACTIVE.value or (
                existing.parent_user_id is not None and existing.child_user_id is not None
            ):
                raise AppError(409, "family.already_joined", "您已经加入了一个家庭，不能重复绑定。")
            await self._abandon_pending_family(session, existing)

        invite, family = await self._resolve_invite(session, token=token)

        # 不能加入自己发出的邀请
        if invite.inviter_user_id == user.id:
            raise AppError(400, "family.invalid_invite", "不能使用自己生成的邀请。")

        # 按空位填入对侧角色
        if family.child_user_id is None and family.parent_user_id is not None:
            if user.role != UserRole.CHILD.value:
                raise AppError(
                    403,
                    "family.child_required",
                    "这份邀请是给子女的，请用子女模式加入。",
                )
            family.child_user_id = user.id
        elif family.parent_user_id is None and family.child_user_id is not None:
            if user.role != UserRole.PARENT.value:
                raise AppError(
                    403,
                    "family.parent_required",
                    "这份邀请是给父母的，请用老人模式加入。",
                )
            family.parent_user_id = user.id
        else:
            raise AppError(409, "family.already_bound", "该家庭已经完成绑定。")

        invite.consumed_at = datetime.now(UTC)
        family.status = FamilyStatus.ACTIVE.value
        await session.commit()
        return await self.get_family_view(session, user)

    async def get_family_view(self, session: AsyncSession, user: User) -> FamilyResponse:
        family = await require_family(session, user)
        parent = (
            await session.get(User, family.parent_user_id)
            if family.parent_user_id is not None
            else None
        )
        child = (
            await session.get(User, family.child_user_id)
            if family.child_user_id is not None
            else None
        )
        # 仅绑定子女可见长辈明文号，避免父母侧接口误带出
        parent_phone: str | None = None
        if user.role == UserRole.CHILD.value and parent is not None and parent.phone_e164:
            parent_phone = parent.phone_e164.removeprefix("+86")

        return FamilyResponse(
            id=family.id,
            parent_user_id=family.parent_user_id,
            child_user_id=family.child_user_id,
            status=family.status,
            parent_display_name=parent.display_name if parent else None,
            child_display_name=child.display_name if child else None,
            parent_phone=parent_phone,
        )
