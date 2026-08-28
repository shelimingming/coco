"""帮我看看业务：识图 + 同图多轮追问；图片仅内存缓存，不落库。"""

from __future__ import annotations

import base64
import logging
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import func, select
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
from coco.modules.vision.image_cache import look_image_cache, normalize_question_key
from coco.modules.vision.schemas import LookFollowUpResponse, LookResponse
from coco.observability.llm_trace import (
    PURPOSE_VISION_FOLLOW_UP,
    PURPOSE_VISION_LOOK,
    bind_llm_trace,
    record_llm_trace,
    reset_llm_trace,
)
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

        tokens = bind_llm_trace(user_id=user.id)
        try:
            result = await self._call_model(
                image_bytes=image_bytes,
                mime=mime,
                question=question,
            )
        finally:
            reset_llm_trace(tokens)
        conversation_id = await self._record_look(
            session,
            user=user,
            result=result,
            question=question,
        )
        # 追问需要原图：只进进程内存，带 TTL
        if conversation_id is not None:
            look_image_cache.put(
                conversation_id,
                image_bytes=image_bytes,
                mime=mime,
                observation=result.scene_description,
            )
        return LookResponse(
            confidence=result.confidence,
            headline=result.headline,
            detail=result.detail,
            safety_note=result.safety_note,
            scene_description=result.scene_description,
            conversation_id=conversation_id,
        )

    async def follow_up(
        self,
        session: AsyncSession,
        *,
        user: User,
        conversation_id: UUID,
        text: str,
    ) -> LookFollowUpResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "auth.role_required", "只有老人模式可以使用帮我看看。")

        cleaned = text.strip()
        if not cleaned:
            raise AppError(400, "vision.empty_question", "请先说想问什么。")

        conversation = await session.get(Conversation, conversation_id)
        if (
            conversation is None
            or conversation.user_id != user.id
            or conversation.channel != ConversationChannel.LOOK.value
        ):
            raise AppError(
                404,
                "vision.conversation_not_found",
                "找不到这次看图记录。请重新拍一张。",
            )

        cached = look_image_cache.get(conversation_id)
        if cached is None:
            raise AppError(
                410,
                "vision.image_expired",
                "这张图过期了。请重新拍一张，再继续问。",
            )

        history = await self._load_text_history(session, conversation_id=conversation_id)
        tokens = bind_llm_trace(user_id=user.id, conversation_id=conversation_id)
        try:
            reply = await self._call_follow_up(
                image_bytes=cached.image_bytes,
                mime=cached.mime,
                history=history,
                user_text=cleaned,
            )
        finally:
            reset_llm_trace(tokens)

        next_seq = await self._next_seq(session, conversation_id=conversation_id)
        session.add(
            ConversationItem(
                conversation_id=conversation_id,
                seq=next_seq,
                kind=ConversationItemKind.USER.value,
                text=cleaned,
            )
        )
        session.add(
            ConversationItem(
                conversation_id=conversation_id,
                seq=next_seq + 1,
                kind=ConversationItemKind.ASSISTANT.value,
                text=reply,
            )
        )
        await session.commit()
        return LookFollowUpResponse(reply_text=reply, conversation_id=conversation_id)

    async def re_analyze(
        self,
        session: AsyncSession,
        *,
        user: User,
        conversation_id: UUID,
        question: str,
    ) -> LookResponse:
        """按当前问题再看原图；同一问只重识一次，新证据追加到临时观察。"""
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "auth.role_required", "只有老人模式可以使用帮我看看。")

        cleaned = question.strip()
        if not cleaned:
            raise AppError(400, "vision.empty_question", "请先说想问什么。")

        conversation = await session.get(Conversation, conversation_id)
        if (
            conversation is None
            or conversation.user_id != user.id
            or conversation.channel != ConversationChannel.LOOK.value
        ):
            raise AppError(
                404,
                "vision.conversation_not_found",
                "找不到这次看图记录。请重新拍一张。",
            )

        cached = look_image_cache.get(conversation_id)
        if cached is None:
            raise AppError(
                410,
                "vision.image_expired",
                "这张图过期了。请重新拍一张，再继续问。",
            )

        question_key = normalize_question_key(cleaned)
        existing = (cached.accumulated_observation or "").strip()
        # 同一问题已重识过：直接返回已有观察，避免反复花钱、编造细节
        if question_key in cached.reanalyzed_keys:
            return LookResponse(
                confidence="high" if existing else "low",
                headline="",
                detail=existing or "我再看也还是看不太清。",
                safety_note="",
                scene_description=existing,
                conversation_id=conversation_id,
            )

        tokens = bind_llm_trace(user_id=user.id, conversation_id=conversation_id)
        try:
            result = await self._call_model(
                image_bytes=cached.image_bytes,
                mime=cached.mime,
                question=cleaned,
            )
        finally:
            reset_llm_trace(tokens)

        merged = _merge_observation(existing, result.scene_description)
        look_image_cache.remember_reanalyze(
            conversation_id,
            question_key=question_key,
            observation=merged,
        )

        next_seq = await self._next_seq(session, conversation_id=conversation_id)
        session.add(
            ConversationItem(
                conversation_id=conversation_id,
                seq=next_seq,
                kind=ConversationItemKind.USER.value,
                text=cleaned,
            )
        )
        session.add(
            ConversationItem(
                conversation_id=conversation_id,
                seq=next_seq + 1,
                kind=ConversationItemKind.ASSISTANT.value,
                text=_spoken_from_look(result),
            )
        )
        await session.commit()
        return LookResponse(
            confidence=result.confidence,
            headline=result.headline,
            detail=result.detail,
            safety_note=result.safety_note,
            scene_description=merged,
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
            await record_llm_trace(
                purpose=PURPOSE_VISION_LOOK,
                modality="vision",
                model=self._settings.vision_model,
                status="skipped",
                error_message="未配置 API Key，识图降级为看不清",
            )
            return unclear_look_result()

        ext = _ALLOWED_MIME[mime]
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

    async def _call_follow_up(
        self,
        *,
        image_bytes: bytes,
        mime: str,
        history: list[tuple[str, str]],
        user_text: str,
    ) -> str:
        key = self._settings.aliyun_api_key
        if key is None or not key.get_secret_value().strip():
            await record_llm_trace(
                purpose=PURPOSE_VISION_FOLLOW_UP,
                modality="vision",
                model=self._settings.vision_model,
                status="skipped",
                error_message="未配置 API Key，追问不可用",
            )
            raise AppError(
                503,
                "vision.unavailable",
                "识图服务暂时不可用。您可以稍后再试，刚才的问题没有保存。",
            )
        ext = _ALLOWED_MIME.get(mime, "jpeg")
        data_url = f"data:image/{ext};base64,{base64.b64encode(image_bytes).decode('ascii')}"
        try:
            client = QwenVisionClient(
                api_key=key,
                model=self._settings.vision_model,
            )
            return await client.follow_up(
                image_data_url=data_url,
                history=history,
                user_text=user_text,
            )
        except AppError:
            raise
        except Exception:
            logger.warning("vision_follow_up_failed", exc_info=True)
            raise AppError(
                502,
                "vision.follow_up_failed",
                "刚才没想好怎么说。请再说一次，数据没有出错写入。",
            ) from None

    async def _record_look(
        self,
        session: AsyncSession,
        *,
        user: User,
        result: LookResult,
        question: str | None,
    ) -> UUID | None:
        """写 LOOK 会话：TOOL 摘要 + 首轮可朗读回复，便于追问历史。"""
        try:
            if result.confidence == "high" and result.headline:
                title = result.headline[:64]
                summary = f"看了一张图：{result.headline}"
            else:
                title = "帮我看看"
                summary = "看了一张图：看不太清"
            if len(summary) > 120:
                summary = summary[:120] + "…"

            spoken = _spoken_from_look(result)
            now = datetime.now(UTC)
            conversation = Conversation(
                user_id=user.id,
                # 追问仍可追加条目；列表侧按 LOOK 展示
                status=ConversationStatus.CLOSED.value,
                channel=ConversationChannel.LOOK.value,
                started_at=now,
                ended_at=now,
                title=title,
            )
            session.add(conversation)
            await session.flush()

            seq = 1
            session.add(
                ConversationItem(
                    conversation_id=conversation.id,
                    seq=seq,
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
                        "scene_description": result.scene_description,
                    },
                    display_summary=summary,
                )
            )
            seq += 1
            opener = (question or "").strip() or "请帮我看看这张图。"
            session.add(
                ConversationItem(
                    conversation_id=conversation.id,
                    seq=seq,
                    kind=ConversationItemKind.USER.value,
                    text=opener,
                )
            )
            seq += 1
            session.add(
                ConversationItem(
                    conversation_id=conversation.id,
                    seq=seq,
                    kind=ConversationItemKind.ASSISTANT.value,
                    text=spoken,
                )
            )
            await session.commit()
            return conversation.id
        except Exception:
            logger.exception("vision_record_look_failed")
            await session.rollback()
            return None

    async def _load_text_history(
        self,
        session: AsyncSession,
        *,
        conversation_id: UUID,
    ) -> list[tuple[str, str]]:
        result = await session.execute(
            select(ConversationItem)
            .where(
                ConversationItem.conversation_id == conversation_id,
                ConversationItem.kind.in_(
                    [
                        ConversationItemKind.USER.value,
                        ConversationItemKind.ASSISTANT.value,
                    ]
                ),
            )
            .order_by(ConversationItem.seq.asc())
        )
        items = list(result.scalars().all())
        history: list[tuple[str, str]] = []
        for item in items:
            text = (item.text or "").strip()
            if not text:
                continue
            role = "user" if item.kind == ConversationItemKind.USER.value else "assistant"
            history.append((role, text))
        return history

    async def _next_seq(self, session: AsyncSession, *, conversation_id: UUID) -> int:
        result = await session.execute(
            select(func.coalesce(func.max(ConversationItem.seq), 0)).where(
                ConversationItem.conversation_id == conversation_id
            )
        )
        current = int(result.scalar_one())
        return current + 1



def _merge_observation(existing: str, addition: str) -> str:
    """把新一轮读图追加到临时观察；新证据放后面，关图后整段丢弃。"""
    old = (existing or "").strip()
    extra = (addition or "").strip()
    if not extra:
        return old
    if not old:
        return extra
    if extra in old:
        return old
    return f"{old}\n\n【补充观察】\n{extra}"


def _spoken_from_look(result: LookResult) -> str:
    """落库用短句：优先 headline+detail；无则截断 scene_description。"""
    parts: list[str] = []
    if result.headline.strip():
        parts.append(result.headline.strip())
    if result.detail.strip():
        parts.append(result.detail.strip())
    if result.safety_note.strip():
        parts.append(result.safety_note.strip())
    if parts:
        return " ".join(parts)
    scene = result.scene_description.strip()
    if scene:
        return scene if len(scene) <= 200 else scene[:200] + "…"
    return "我看不太清这上面的字。您可以重新拍一张。"
