"""父母端对话历史：落库与查询；默认不同步子女。"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import get_settings
from coco.database import get_session_factory
from coco.errors import AppError
from coco.models.conversation import (
    Conversation,
    ConversationChannel,
    ConversationItem,
    ConversationItemKind,
    ConversationStatus,
)
from coco.models.user import User, UserRole
from coco.modules.conversations.schemas import (
    ConversationDetailResponse,
    ConversationItemResponse,
    ConversationListItem,
)
from coco.observability.llm_trace import bind_llm_trace, reset_llm_trace
from coco.providers.mem0_memory import get_mem0_client
from coco.providers.qwen_text import fallback_conversation_title, title_or_fallback

logger = logging.getLogger(__name__)

_PREVIEW_MAX = 48
# 标题生成只取前若干条，避免把整段长通话塞进 prompt
_TITLE_TRANSCRIPT_MAX_ITEMS = 12
_TITLE_TRANSCRIPT_MAX_CHARS = 1200


def tool_display_summary(tool_name: str, arguments: dict[str, Any], result: dict[str, Any]) -> str:
    """把工具调用转成父母可懂的白话，不暴露 JSON。"""
    status = str(result.get("status") or "")
    need_confirm = status == "need_confirmation"

    if tool_name == "recall_memory":
        return "可可回想了记住的事"

    if tool_name == "save_memory":
        content = str(arguments.get("content") or result.get("content") or "").strip()
        return f"帮你记住：{content}" if content else "帮你记住了一件事"

    if tool_name == "create_reminder":
        title = str(arguments.get("title") or result.get("title") or "").strip()
        if need_confirm:
            return f"还在问你要不要设提醒：{title}" if title else "还在问你要不要设提醒"
        return f"帮你设了提醒：{title}" if title else "帮你设了提醒"

    if tool_name == "confirm_reminder":
        if need_confirm:
            return "还在问你要不要确认提醒"
        return "帮你确认了提醒"

    if tool_name == "list_reminders":
        return "可可查看了你的提醒"

    if tool_name == "list_memories":
        # 旧通话可能仍有读记忆工具记录
        return "可可查看了你记住的事"

    if tool_name == "web_search":
        if status == "error":
            return "可可没查到网上的消息"
        return "可可查了网上的消息"

    if tool_name == "share_to_child":
        summary = str(arguments.get("summary") or result.get("summary") or "").strip()
        if need_confirm:
            return f"还在问你要不要告诉家人：{summary}" if summary else "还在问你要不要告诉家人"
        return f"准备告诉家人：{summary}" if summary else "准备告诉家人一件事"

    if tool_name == "open_screen":
        label = str(result.get("label") or "").strip()
        if status == "error":
            return "可可没能打开那个页面"
        return f"打开了「{label}」" if label else "打开了一个页面"

    if tool_name == "look_image":
        headline = str(result.get("headline") or "").strip()
        confidence = str(result.get("confidence") or "").strip().lower()
        if confidence == "low" or not headline:
            return "看了一张图：看不太清"
        return f"看了一张图：{headline}"

    if status == "error":
        return "刚才想帮你办事，但没办成"
    return f"可可调用了：{tool_name}"


def should_list_in_history(items: list[ConversationItem]) -> bool:
    """历史列表是否展示：仅可可主动打招呼、或完全无内容的会话不展示。"""
    if not items:
        return False
    for item in items:
        if item.kind == ConversationItemKind.TOOL.value:
            return True
        if item.kind == ConversationItemKind.USER.value and (item.text or "").strip():
            return True
    # 只剩助手台词（多为进首页自动开场），不算有效对话
    return False


def _preview_from_items(items: list[ConversationItem]) -> str:
    for item in items:
        if item.kind in {ConversationItemKind.USER.value, ConversationItemKind.ASSISTANT.value}:
            text = (item.text or "").strip()
            if text:
                if len(text) > _PREVIEW_MAX:
                    return text[:_PREVIEW_MAX] + "…"
                return text
        if item.kind == ConversationItemKind.TOOL.value and item.display_summary:
            summary = item.display_summary.strip()
            if summary:
                if len(summary) > _PREVIEW_MAX:
                    return summary[:_PREVIEW_MAX] + "…"
                return summary
    return "这次还没有记下说话内容"


def transcript_for_title(items: list[ConversationItem]) -> str:
    """拼给 LLM 的对话摘录；优先用户/可可原话，工具用白话摘要。"""
    lines: list[str] = []
    for item in items[:_TITLE_TRANSCRIPT_MAX_ITEMS]:
        if item.kind == ConversationItemKind.USER.value:
            text = (item.text or "").strip()
            if text:
                lines.append(f"用户：{text}")
        elif item.kind == ConversationItemKind.ASSISTANT.value:
            text = (item.text or "").strip()
            if text:
                lines.append(f"可可：{text}")
        elif item.kind == ConversationItemKind.TOOL.value and item.display_summary:
            summary = item.display_summary.strip()
            if summary:
                lines.append(f"（做事）{summary}")
    transcript = "\n".join(lines)
    if len(transcript) > _TITLE_TRANSCRIPT_MAX_CHARS:
        return transcript[:_TITLE_TRANSCRIPT_MAX_CHARS]
    return transcript


def _parse_result_json(output: str) -> dict[str, Any]:
    try:
        parsed = json.loads(output)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass
    return {"raw": output}


class ConversationService:
    async def list_for_user(
        self, session: AsyncSession, *, user: User
    ) -> list[ConversationListItem]:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "conversation.parent_required", "只有老人模式可以查看聊天记录。")
        result = await session.execute(
            select(Conversation)
            .where(Conversation.user_id == user.id)
            .order_by(Conversation.started_at.desc())
        )
        conversations = list(result.scalars().all())
        if not conversations:
            return []

        ids = [c.id for c in conversations]
        items_result = await session.execute(
            select(ConversationItem)
            .where(ConversationItem.conversation_id.in_(ids))
            .order_by(ConversationItem.conversation_id, ConversationItem.seq.asc())
        )
        by_conversation: dict[UUID, list[ConversationItem]] = {cid: [] for cid in ids}
        for item in items_result.scalars().all():
            by_conversation.setdefault(item.conversation_id, []).append(item)

        return [
            ConversationListItem(
                id=c.id,
                started_at=c.started_at,
                ended_at=c.ended_at,
                status=c.status,
                channel=c.channel,
                title=c.title,
                preview=_preview_from_items(items),
            )
            for c in conversations
            if should_list_in_history(items := by_conversation.get(c.id, []))
        ]

    async def get_for_user(
        self, session: AsyncSession, *, user: User, conversation_id: UUID
    ) -> ConversationDetailResponse:
        if user.role != UserRole.PARENT.value:
            raise AppError(403, "conversation.parent_required", "只有老人模式可以查看聊天记录。")
        conversation = await session.get(Conversation, conversation_id)
        if conversation is None or conversation.user_id != user.id:
            raise AppError(404, "conversation.not_found", "找不到这段聊天记录。")

        result = await session.execute(
            select(ConversationItem)
            .where(ConversationItem.conversation_id == conversation.id)
            .order_by(ConversationItem.seq.asc())
        )
        items = [
            ConversationItemResponse(
                id=item.id,
                seq=item.seq,
                kind=item.kind,
                text=item.text,
                tool_name=item.tool_name,
                display_summary=item.display_summary,
                created_at=item.created_at,
            )
            for item in result.scalars().all()
        ]
        return ConversationDetailResponse(
            id=conversation.id,
            started_at=conversation.started_at,
            ended_at=conversation.ended_at,
            status=conversation.status,
            channel=conversation.channel,
            title=conversation.title,
            items=items,
        )


async def start_conversation(user_id: UUID) -> UUID | None:
    """通话开始时创建会话；失败返回 None，不打断语音。"""
    try:
        factory = get_session_factory()
        async with factory() as session:
            conversation = Conversation(
                user_id=user_id,
                status=ConversationStatus.ACTIVE.value,
                channel=ConversationChannel.VOICE_REALTIME.value,
                started_at=datetime.now(UTC),
            )
            session.add(conversation)
            await session.commit()
            await session.refresh(conversation)
            return conversation.id
    except Exception:
        logger.exception("conversation_start_failed")
        return None


async def append_utterance(
    conversation_id: UUID,
    *,
    seq: int,
    kind: str,
    text: str,
) -> None:
    """追加用户/助手最终转写；失败只打日志。"""
    try:
        factory = get_session_factory()
        async with factory() as session:
            session.add(
                ConversationItem(
                    conversation_id=conversation_id,
                    seq=seq,
                    kind=kind,
                    text=text.strip(),
                )
            )
            await session.commit()
    except Exception:
        logger.exception("conversation_append_utterance_failed id=%s seq=%s", conversation_id, seq)


async def append_tool_call(
    conversation_id: UUID,
    *,
    seq: int,
    tool_name: str,
    arguments: dict[str, Any],
    result_output: str,
) -> None:
    """追加工具调用记录；失败只打日志。"""
    try:
        result = _parse_result_json(result_output)
        summary = tool_display_summary(tool_name, arguments, result)
        factory = get_session_factory()
        async with factory() as session:
            session.add(
                ConversationItem(
                    conversation_id=conversation_id,
                    seq=seq,
                    kind=ConversationItemKind.TOOL.value,
                    tool_name=tool_name,
                    arguments_json=arguments,
                    result_json=result,
                    display_summary=summary,
                )
            )
            await session.commit()
    except Exception:
        logger.exception("conversation_append_tool_failed id=%s seq=%s", conversation_id, seq)


async def _refine_conversation_title(
    conversation_id: UUID, *, transcript: str, preview: str, user_id: UUID | None = None
) -> None:
    """后台用 LLM 覆盖兜底标题；失败不影响已结束的会话。"""
    tokens = bind_llm_trace(user_id=user_id, conversation_id=conversation_id)
    try:
        settings = get_settings()
        title_result = await title_or_fallback(
            api_key=settings.aliyun_api_key,
            model=settings.text_model,
            transcript=transcript,
            preview=preview,
        )
        if not title_result.generated:
            return
        factory = get_session_factory()
        async with factory() as session:
            conversation = await session.get(Conversation, conversation_id)
            if conversation is None:
                return
            conversation.title = title_result.title
            await session.commit()
    except Exception:
        logger.exception("conversation_title_refine_failed id=%s", conversation_id)
    finally:
        reset_llm_trace(tokens)


def _messages_for_mem0(items: list[ConversationItem]) -> list[dict[str, str]]:
    """只取用户/助手转写，供 Mem0 抽取；跳过工具行。"""
    messages: list[dict[str, str]] = []
    for item in items:
        text = (item.text or "").strip()
        if not text:
            continue
        if item.kind == ConversationItemKind.USER.value:
            messages.append({"role": "user", "content": text})
        elif item.kind == ConversationItemKind.ASSISTANT.value:
            messages.append({"role": "assistant", "content": text})
    return messages


async def _extract_memories_from_conversation(
    conversation_id: UUID,
    *,
    user_id: UUID,
    messages: list[dict[str, str]],
) -> None:
    """后台把本通对话交给 Mem0 自动抽取；失败只打日志。"""
    if not messages:
        return
    tokens = bind_llm_trace(user_id=user_id, conversation_id=conversation_id)
    try:
        await get_mem0_client().add_from_messages(
            user_id=str(user_id),
            messages=messages,
        )
    except Exception:
        logger.exception(
            "conversation_memory_extract_failed id=%s user_id=%s",
            conversation_id,
            user_id,
        )
    finally:
        reset_llm_trace(tokens)


async def end_conversation(conversation_id: UUID, *, status: str) -> None:
    """结束会话并异步生成标题、抽取记忆；失败只打日志，不打断语音挂断。"""
    try:
        factory = get_session_factory()
        # 先落库结束状态 + 兜底标题，挂断路径尽快返回
        user_id: UUID | None = None
        mem0_messages: list[dict[str, str]] = []
        async with factory() as session:
            conversation = await session.get(Conversation, conversation_id)
            if conversation is None:
                return
            user_id = conversation.user_id
            items_result = await session.execute(
                select(ConversationItem)
                .where(ConversationItem.conversation_id == conversation_id)
                .order_by(ConversationItem.seq.asc())
            )
            items = list(items_result.scalars().all())
            preview = _preview_from_items(items)
            transcript = transcript_for_title(items)
            mem0_messages = _messages_for_mem0(items)
            conversation.ended_at = datetime.now(UTC)
            conversation.status = status
            conversation.title = fallback_conversation_title(preview)
            await session.commit()

        # LLM 标题在后台生成，避免拖慢 WebSocket 收尾
        asyncio.create_task(
            _refine_conversation_title(
                conversation_id,
                transcript=transcript,
                preview=preview,
                user_id=user_id,
            ),
            name=f"conversation-title-{conversation_id}",
        )
        # 记忆抽取同样后台跑；本通说的话要下次建连才注入
        if user_id is not None and mem0_messages:
            asyncio.create_task(
                _extract_memories_from_conversation(
                    conversation_id,
                    user_id=user_id,
                    messages=mem0_messages,
                ),
                name=f"conversation-mem0-{conversation_id}",
            )
    except Exception:
        logger.exception("conversation_end_failed id=%s", conversation_id)
