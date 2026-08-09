"""家庭绑定业务：邀请码 + 1 父母 / 1 子女。"""

from __future__ import annotations

import secrets
from datetime import UTC, datetime, timedelta

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings
from coco.errors import AppError
from coco.models.family import Family, FamilyInvite, FamilyStatus
from coco.models.user import User, UserRole
from coco.modules.family.schemas import (
    FamilyInviteCreateResponse,
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


class FamilyService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    async def create_invite(
        self, session: AsyncSession, *, user: User
    ) -> FamilyInviteCreateResponse:
        # 服务端鉴权是最终判断：只有父母可发起邀请
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "family.parent_required", "只有老人模式可以生成邀请码。")

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
                "已经绑定了子女，不能再生成邀请码。如需更换请先解除绑定（MVP 暂不支持）。",
            )

        now = datetime.now(UTC)
        code = f"{secrets.randbelow(1_000_000):06d}"
        invite = FamilyInvite(
            code=code,
            inviter_user_id=user.id,
            family_id=family.id,
            expires_at=now + timedelta(minutes=self._settings.family_invite_ttl_minutes),
            created_at=now,
        )
        session.add(invite)
        await session.commit()
        await session.refresh(invite)
        return FamilyInviteCreateResponse(
            code=invite.code,
            expires_at=invite.expires_at,
            family_id=family.id,
        )

    async def join_family(self, session: AsyncSession, *, user: User, code: str) -> FamilyResponse:
        if user.role != UserRole.CHILD.value:
            raise AppError(403, "family.child_required", "只有子女模式可以用邀请码加入家庭。")

        existing = await get_family(session, user)
        if existing is not None:
            raise AppError(409, "family.already_joined", "您已经加入了一个家庭，不能重复绑定。")

        normalized = code.strip()
        now = datetime.now(UTC)
        result = await session.execute(
            select(FamilyInvite, Family)
            .join(Family, Family.id == FamilyInvite.family_id)
            .where(
                FamilyInvite.code == normalized,
                FamilyInvite.consumed_at.is_(None),
                FamilyInvite.expires_at > now,
            )
            .order_by(FamilyInvite.created_at.desc())
        )
        row = result.first()
        if row is None:
            raise AppError(
                400,
                "family.invalid_invite",
                "邀请码无效或已过期。请向父母重新索取，刚才没有建立任何家庭关系。",
            )
        invite, family = row
        if family.child_user_id is not None:
            raise AppError(409, "family.already_bound", "该家庭已经绑定了子女。")

        invite.consumed_at = now
        family.child_user_id = user.id
        family.status = FamilyStatus.ACTIVE.value
        await session.commit()
        return await self.get_family_view(session, user)

    async def get_family_view(self, session: AsyncSession, user: User) -> FamilyResponse:
        family = await require_family(session, user)
        parent = await session.get(User, family.parent_user_id)
        child = (
            await session.get(User, family.child_user_id)
            if family.child_user_id is not None
            else None
        )
        return FamilyResponse(
            id=family.id,
            parent_user_id=family.parent_user_id,
            child_user_id=family.child_user_id,
            status=family.status,
            parent_display_name=parent.display_name if parent else None,
            child_display_name=child.display_name if child else None,
        )
