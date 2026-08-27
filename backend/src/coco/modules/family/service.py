"""家庭绑定业务：邀请链接 + 1 父母 / 1 子女。"""

from __future__ import annotations

import secrets
from datetime import UTC, datetime

from sqlalchemy import delete, or_, select, update
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

# expires_at 列为 NOT NULL，用远期哨兵表示永不过期
_NEVER_EXPIRES_AT = datetime(2126, 1, 1, tzinfo=UTC)
_CODE_ATTEMPTS = 5


async def get_family(session: AsyncSession, user: User) -> Family | None:
    """按当前用户查找所属家庭（父母或子女侧）；已 dissolved 的不算绑定。"""
    result = await session.execute(
        select(Family).where(
            Family.status != FamilyStatus.DISSOLVED.value,
            or_(
                Family.parent_user_id == user.id,
                Family.child_user_id == user.id,
            ),
        )
    )
    return result.scalar_one_or_none()


async def require_family(session: AsyncSession, user: User) -> Family:
    family = await get_family(session, user)
    if family is None:
        raise AppError(404, "family.not_found", "还没有绑定家庭。请先完成父母与子女的绑定。")
    return family


def _target_role_of(family: Family) -> str:
    """从家庭空位推断这份邀请要给谁。"""
    if family.parent_user_id is not None and family.child_user_id is None:
        return UserRole.CHILD.value
    if family.child_user_id is not None and family.parent_user_id is None:
        return UserRole.PARENT.value
    raise AppError(409, "family.already_bound", "该家庭已经完成绑定。")


def _invite_url(settings: Settings, code: str) -> str:
    return f"{settings.public_base_url.rstrip('/')}/i/{code}"


async def _new_invite_code(session: AsyncSession) -> str:
    """生成 8 字符 URL 安全码；冲突时重试。"""
    for _ in range(_CODE_ATTEMPTS):
        # token_urlsafe(6) 恰好 8 字符，用满 code 列长度
        code = secrets.token_urlsafe(6)
        if len(code) != 8:
            continue
        exists = await session.scalar(select(FamilyInvite.id).where(FamilyInvite.code == code))
        if exists is None:
            return code
    raise AppError(500, "family.invite_failed", "邀请链接没生成成功。请稍后再试，没有建立任何家庭关系。")


class FamilyService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def _to_create_response(
        self, invite: FamilyInvite, family: Family, inviter: User
    ) -> FamilyInviteCreateResponse:
        return FamilyInviteCreateResponse(
            code=invite.code,
            invite_url=_invite_url(self._settings, invite.code),
            target_role=_target_role_of(family),
            inviter_display_name=inviter.display_name,
            family_id=family.id,
        )

    async def create_invite(
        self, session: AsyncSession, *, user: User
    ) -> FamilyInviteCreateResponse:
        if user.role == UserRole.PARENT.value:
            family = await session.scalar(
                select(Family).where(
                    Family.parent_user_id == user.id,
                    Family.status != FamilyStatus.DISSOLVED.value,
                )
            )
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
                    "已经绑定了子女，不能再邀请。如需更换请先在家庭页解除绑定。",
                )
        elif user.role == UserRole.CHILD.value:
            family = await session.scalar(
                select(Family).where(
                    Family.child_user_id == user.id,
                    Family.status != FamilyStatus.DISSOLVED.value,
                )
            )
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
                    "已经绑定了父母，不能再邀请。如需更换请先在家庭页解除绑定。",
                )
        else:
            raise AppError(403, "family.role_required", "当前角色无法发出邀请。")

        # 链接不过期：未消费邀请直接复用，避免重复点击堆出多条链接
        existing = await session.scalar(
            select(FamilyInvite)
            .where(
                FamilyInvite.family_id == family.id,
                FamilyInvite.consumed_at.is_(None),
            )
            .order_by(FamilyInvite.created_at.desc())
        )
        if existing is not None:
            return self._to_create_response(existing, family, user)

        now = datetime.now(UTC)
        invite = FamilyInvite(
            code=await _new_invite_code(session),
            inviter_user_id=user.id,
            family_id=family.id,
            expires_at=_NEVER_EXPIRES_AT,
            created_at=now,
        )
        session.add(invite)
        await session.commit()
        await session.refresh(invite)
        return self._to_create_response(invite, family, user)

    async def preview_invite(
        self, session: AsyncSession, *, code: str
    ) -> FamilyInvitePreviewResponse:
        """免鉴权预览：只返回邀请人与目标角色，供落地页登录前展示。"""
        normalized = code.strip()
        invite = await session.scalar(
            select(FamilyInvite)
            .where(FamilyInvite.code == normalized)
            .order_by(FamilyInvite.created_at.desc())
        )
        if invite is None:
            return FamilyInvitePreviewResponse(status="not_found")
        if invite.consumed_at is not None:
            return FamilyInvitePreviewResponse(status="consumed")

        family = await session.get(Family, invite.family_id)
        inviter = await session.get(User, invite.inviter_user_id)
        if family is None or inviter is None:
            return FamilyInvitePreviewResponse(status="not_found")
        try:
            target_role = _target_role_of(family)
        except AppError:
            return FamilyInvitePreviewResponse(status="consumed")
        return FamilyInvitePreviewResponse(
            status="valid",
            inviter_display_name=inviter.display_name,
            target_role=target_role,
            family_id=family.id,
        )

    async def _abandon_pending_family(self, session: AsyncSession, family: Family) -> None:
        """加入对方家庭前，放弃自己未完成的 pending 家庭及未消费邀请。"""
        await session.execute(delete(FamilyInvite).where(FamilyInvite.family_id == family.id))
        await session.delete(family)
        await session.flush()

    async def join_family(self, session: AsyncSession, *, user: User, code: str) -> FamilyResponse:
        normalized = code.strip()
        now = datetime.now(UTC)
        # 邀请链接不过期，只校验未消费；先解析邀请，便于判断是否与当前家庭冲突
        result = await session.execute(
            select(FamilyInvite, Family)
            .join(Family, Family.id == FamilyInvite.family_id)
            .where(
                FamilyInvite.code == normalized,
                FamilyInvite.consumed_at.is_(None),
            )
            .order_by(FamilyInvite.created_at.desc())
        )
        row = result.first()
        if row is None:
            raise AppError(
                400,
                "family.invalid_invite",
                "邀请链接无效或已被使用。请让家人重新发一条，刚才没有建立任何家庭关系。",
            )
        invite, family = row

        existing = await get_family(session, user)
        if existing is not None:
            # 已 active：禁止换绑；同一家庭重复加入视为成功
            if existing.status == FamilyStatus.ACTIVE.value or (
                existing.parent_user_id is not None and existing.child_user_id is not None
            ):
                if existing.id == family.id:
                    return await self.get_family_view(session, user)
                raise AppError(
                    409,
                    "family.already_joined",
                    "您已经绑定了其他家人。如需接受这份邀请，请先在 App 家庭页解除当前绑定后再加入。",
                )
            await self._abandon_pending_family(session, existing)

        # 不能加入自己发出的邀请
        if invite.inviter_user_id == user.id:
            raise AppError(400, "family.invalid_invite", "不能使用自己发出的邀请链接。")

        # 按空位填入对侧角色
        if family.child_user_id is None and family.parent_user_id is not None:
            if user.role != UserRole.CHILD.value:
                raise AppError(
                    403,
                    "family.child_required",
                    "这份邀请是给子女的，请用子女身份打开链接并登录。",
                )
            family.child_user_id = user.id
        elif family.parent_user_id is None and family.child_user_id is not None:
            if user.role != UserRole.PARENT.value:
                raise AppError(
                    403,
                    "family.parent_required",
                    "这份邀请是给父母的，请用老人身份打开链接并登录。",
                )
            family.parent_user_id = user.id
        else:
            raise AppError(409, "family.already_bound", "该家庭已经完成绑定。")

        family.status = FamilyStatus.ACTIVE.value
        # 家庭已满，该家庭其余未消费链接一并作废
        await session.execute(
            update(FamilyInvite)
            .where(
                FamilyInvite.family_id == family.id,
                FamilyInvite.consumed_at.is_(None),
            )
            .values(consumed_at=now)
        )
        await session.commit()
        return await self.get_family_view(session, user)

    async def unbind_family(self, session: AsyncSession, *, user: User) -> None:
        """软解绑：保留 family_messages，只断开用户与 family 的关联。"""
        family = await require_family(session, user)
        if (
            family.status != FamilyStatus.ACTIVE.value
            or family.parent_user_id is None
            or family.child_user_id is None
        ):
            raise AppError(
                400,
                "family.not_active",
                "还没有完成绑定，无需解除。",
            )

        now = datetime.now(UTC)
        # 作废未消费邀请，避免旧链接误绑
        await session.execute(
            update(FamilyInvite)
            .where(
                FamilyInvite.family_id == family.id,
                FamilyInvite.consumed_at.is_(None),
            )
            .values(consumed_at=now)
        )
        family.parent_user_id = None
        family.child_user_id = None
        family.status = FamilyStatus.DISSOLVED.value
        await session.commit()

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
