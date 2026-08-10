"""帮我看看业务：识图一次，落文本摘要到对话历史；图片不落库。"""

from __future__ import annotations

import base64
import logging
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings
from coco.errors import AppError
from coco.models.conversation import (
    Conversation,
    ConversationChannel,
    ConversationItem,
    ConversationItemKind,
    ConversationStatus,
)
from coco.models.user import User, UserRole
from coco.modules.vision.schemas import LookResponse
from coco.providers.qwen_vision import (
    LookResult,
    QwenVisionClient,
    unclear_look_result,
)

logger = logging.getLogger(__name__)

# 老人端上传上限：约 4MB，避免撑爆百炼请求
_MAX_IMAGE_BYTES = 4 * 1024 * 1024
_ALLOWED_MIME = {
    "image/jpeg": "jpeg",
    "image/jpg": "jpeg",
    "image/png": "png",
    "image/webp": "webp",
}


class VisionService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    async def look(
        self,
        session: AsyncSession,
        *,
        user: User,
        image_bytes: bytes,
        content_type: str | None,
        question: str | None = None,
    ) -> LookResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "auth.role_required", "只有老人模式可以使用帮我看看。")

        if not image_bytes:
            raise AppError(
                400,
                "vision.empty_image",
                "没有收到照片。请重新拍一张或从相册选一张。",
            )
        if len(image_bytes) > _MAX_IMAGE_BYTES:
            raise AppError(
                400,
                "vision.image_too_large",
                "照片太大了。请离近一点重拍，或换一张更小的图。刚才没有上传成功。",
            )

        mime = (content_type or "image/jpeg").split(";")[0].strip().lower()
        if mime not in _ALLOWED_MIME:
            raise AppError(
                400,
                "vision.unsupported_image",
                "暂时只支持常见照片格式。请用手机重新拍一张。",
            )

        result = await self._call_model(
            image_bytes=image_bytes,
            mime=mime,
            question=question,
        )
        conversation_id = await self._record_look(
            session,
            user=user,
            result=result,
            question=question,
        )
        return LookResponse(
            confidence=result.confidence,
            headline=result.headline,
            detail=result.detail,
            safety_note=result.safety_note,
            conversation_id=conversation_id,
        )

    async def _call_model(
        self,
        *,
        image_bytes: bytes,
        mime: str,
        question: str | None,
    ) -> LookResult:
        key = self._settings.aliyun_api_key
        if key is None or not key.get_secret_value().strip():
            return unclear_look_result()

        ext = _ALLOWED_MIME[mime]
        # data URL 仅在本次请求内存中使用，不写文件、不入库
        data_url = f"data:image/{ext};base64,{base64.b64encode(image_bytes).decode('ascii')}"
        try:
            client = QwenVisionClient(
                api_key=key,
                model=self._settings.vision_model,
            )
            return await client.look(image_data_url=data_url, question=question)
        except Exception:
            logger.warning("vision_look_failed", exc_info=True)
            return unclear_look_result()

    async def _record_look(
        self,
        session: AsyncSession,
        *,
        user: User,
        result: LookResult,
        question: str | None,
    ) -> UUID | None:
        """写一条 LOOK 会话 + TOOL 摘要；失败不影响识图结果返回。"""
        try:
            if result.confidence == "high" and result.headline:
                title = result.headline[:64]
                summary = f"看了一张图：{result.headline}"
            else:
                title = "帮我看看"
                summary = "看了一张图：看不太清"
            if len(summary) > 120:
                summary = summary[:120] + "…"

            now = datetime.now(UTC)
            conversation = Conversation(
                user_id=user.id,
                status=ConversationStatus.CLOSED.value,
                channel=ConversationChannel.LOOK.value,
                started_at=now,
                ended_at=now,
                title=title,
            )
            session.add(conversation)
            await session.flush()

            session.add(
                ConversationItem(
                    conversation_id=conversation.id,
                    seq=1,
                    kind=ConversationItemKind.TOOL.value,
                    tool_name="look_image",
                    arguments_json={
                        "question": (question or "").strip() or None,
                    },
                    result_json={
                        "confidence": result.confidence,
                        "headline": result.headline,
                        "detail": result.detail,
                        "safety_note": result.safety_note,
                    },
                    display_summary=summary,
                )
            )
            await session.commit()
            return conversation.id
        except Exception:
            logger.exception("vision_record_look_failed")
            await session.rollback()
            return None
