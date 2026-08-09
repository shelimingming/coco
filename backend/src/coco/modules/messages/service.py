"""子女报平安：转译预览 → 确认发送。"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings
from coco.errors import AppError
from coco.models.care import FamilyMessage, FamilyMessageKind
from coco.models.family import FamilyStatus
from coco.models.notification import Notification, NotificationType
from coco.models.user import User, UserRole
from coco.modules.family.service import require_family
from coco.modules.messages.schemas import (
    FamilyMessageResponse,
    MessagePreviewResponse,
    MessageSendRequest,
)
from coco.providers.qwen_text import translate_or_passthrough


def _to_response(msg: FamilyMessage) -> FamilyMessageResponse:
    return FamilyMessageResponse(
        id=msg.id,
        family_id=msg.family_id,
        from_user_id=msg.from_user_id,
        to_user_id=msg.to_user_id,
        kind=msg.kind,
        original_text=msg.original_text,
        delivered_text=msg.delivered_text,
        acknowledged_at=msg.acknowledged_at,
        created_at=msg.created_at,
    )


class MessageService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    async def preview(
        self, session: AsyncSession, *, user: User, text: str
    ) -> MessagePreviewResponse:
        if user.role != UserRole.CHILD.value:
            raise AppError(403, "message.child_required", "只有子女模式可以发送报平安。")
        family = await require_family(session, user)
        if family.child_user_id != user.id or family.status != FamilyStatus.ACTIVE.value:
            raise AppError(400, "message.family_inactive", "家庭尚未完成绑定，不能报平安。")

        result = await translate_or_passthrough(
            api_key=self._settings.aliyun_api_key,
            model=self._settings.text_model,
            text=text,
            child_name=user.display_name or "孩子",
        )
        return MessagePreviewResponse(
            original_text=text.strip(),
            delivered_text=result.text,
            translated=result.translated,
        )

    async def send(
        self, session: AsyncSession, *, user: User, body: MessageSendRequest
    ) -> FamilyMessageResponse:
        if user.role != UserRole.CHILD.value:
            raise AppError(403, "message.child_required", "只有子女模式可以发送报平安。")
        family = await require_family(session, user)
        if (
            family.child_user_id != user.id
            or family.parent_user_id is None
            or family.status != FamilyStatus.ACTIVE.value
        ):
            raise AppError(400, "message.family_inactive", "家庭尚未完成绑定，不能报平安。")

        msg = FamilyMessage(
            family_id=family.id,
            from_user_id=user.id,
            to_user_id=family.parent_user_id,
            kind=FamilyMessageKind.CHILD_STATUS.value,
            original_text=body.original_text.strip(),
            delivered_text=body.delivered_text.strip(),
        )
        session.add(msg)
        session.add(
            Notification(
                user_id=family.parent_user_id,
                type=NotificationType.CHILD_STATUS.value,
                title="子女报平安",
                body=msg.delivered_text,
                payload={"message_id": str(msg.id)},
            )
        )
        await session.commit()
        await session.refresh(msg)
        return _to_response(msg)

    async def list_for_user(
        self, session: AsyncSession, *, user: User, limit: int = 30
    ) -> list[FamilyMessageResponse]:
        family = await require_family(session, user)
        result = await session.execute(
            select(FamilyMessage)
            .where(FamilyMessage.family_id == family.id)
            .order_by(FamilyMessage.created_at.desc())
            .limit(min(limit, 100))
        )
        return [_to_response(m) for m in result.scalars().all()]
