"""模型调试时间线：按用户查看全部大模型调用。"""

from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from coco.models.conversation import Conversation
from coco.models.llm_trace import LlmTrace
from coco.models.user import User
from coco.observability.llm_trace import (
    PURPOSE_MEM0_EXTRACT,
    PURPOSE_MEM0_SEARCH,
    PURPOSE_TEXT_TITLE,
    PURPOSE_TEXT_TRANSLATE,
    PURPOSE_VISION_FOLLOW_UP,
    PURPOSE_VISION_INJECT,
    PURPOSE_VISION_LOOK,
    PURPOSE_VOICE_SESSION,
    PURPOSE_VOICE_TOOL,
    PURPOSE_VOICE_TURN,
)
from sqladmin import BaseView, expose
from sqlalchemy import or_, select
from starlette.requests import Request
from starlette.responses import Response

from coco_admin.database import get_session_factory

PURPOSE_LABELS: dict[str, str] = {
    PURPOSE_VOICE_SESSION: "语音建连",
    PURPOSE_VOICE_TURN: "语音一轮",
    PURPOSE_VOICE_TOOL: "语音工具",
    PURPOSE_VISION_LOOK: "识图",
    PURPOSE_VISION_FOLLOW_UP: "识图追问",
    PURPOSE_VISION_INJECT: "识图注入语音",
    PURPOSE_TEXT_TITLE: "生成标题",
    PURPOSE_TEXT_TRANSLATE: "报平安转译",
    PURPOSE_MEM0_EXTRACT: "记忆抽取",
    PURPOSE_MEM0_SEARCH: "记忆检索",
}

STATUS_LABELS = {"ok": "成功", "error": "失败", "skipped": "跳过"}


def _pretty(value: Any) -> str:
    if value is None:
        return ""
    try:
        return json.dumps(value, ensure_ascii=False, indent=2, default=str)
    except TypeError:
        return str(value)


def _purpose_label(purpose: str) -> str:
    return PURPOSE_LABELS.get(purpose, purpose)


def _status_label(status: str) -> str:
    return STATUS_LABELS.get(status, status)


def _summarize(trace: LlmTrace) -> str:
    req = trace.request_json if isinstance(trace.request_json, dict) else {}
    resp = trace.response_json if isinstance(trace.response_json, dict) else {}
    if trace.purpose == PURPOSE_VOICE_TURN:
        user = str(req.get("user") or "")[:40]
        assistant = str(resp.get("assistant") or "")[:40]
        return f"用户：{user or '—'} / 可可：{assistant or '—'}"
    if trace.purpose == PURPOSE_VOICE_TOOL:
        return str(req.get("name") or "工具")
    if trace.purpose == PURPOSE_TEXT_TITLE:
        return str(resp.get("title") or resp.get("content") or "")[:40]
    if trace.purpose == PURPOSE_TEXT_TRANSLATE:
        return str(resp.get("content") or req.get("text") or "")[:60]
    if trace.purpose in {PURPOSE_VISION_LOOK, PURPOSE_VISION_FOLLOW_UP}:
        return str(resp.get("headline") or resp.get("content") or "")[:60]
    if trace.error_message:
        return trace.error_message[:80]
    return ""


def _decorate(traces: list[LlmTrace]) -> list[dict[str, Any]]:
    items = []
    for trace in traces:
        items.append(
            {
                "trace": trace,
                "purpose_label": _purpose_label(trace.purpose),
                "status_label": _status_label(trace.status),
                "summary": _summarize(trace),
                "request_pretty": _pretty(trace.request_json),
                "response_pretty": _pretty(trace.response_json),
                "usage_pretty": _pretty(trace.usage_json),
            }
        )
    return items


async def _load_timeline(
    *,
    user_id: UUID,
    purpose: str | None,
    status: str | None,
    hours: int,
) -> tuple[User | None, list[dict[str, Any]]]:
    factory = get_session_factory()
    async with factory() as session:
        user = await session.get(User, user_id)
        if user is None:
            return None, []
        stmt = select(LlmTrace).where(LlmTrace.user_id == user_id)
        if purpose:
            stmt = stmt.where(LlmTrace.purpose == purpose)
        if status:
            stmt = stmt.where(LlmTrace.status == status)
        if hours > 0:
            since = datetime.now(UTC) - timedelta(hours=hours)
            stmt = stmt.where(LlmTrace.started_at >= since)
        stmt = stmt.order_by(LlmTrace.started_at.desc()).limit(500)
        traces = list((await session.scalars(stmt)).all())
        conv_ids = {t.conversation_id for t in traces if t.conversation_id is not None}
        conversations: dict[UUID, Conversation] = {}
        if conv_ids:
            conversations = {
                c.id: c
                for c in (
                    await session.scalars(select(Conversation).where(Conversation.id.in_(conv_ids)))
                ).all()
            }

        grouped: dict[str, dict[str, Any]] = {}
        order: list[str] = []
        for trace in traces:
            key = str(trace.conversation_id) if trace.conversation_id else f"loose:{trace.id}"
            if key not in grouped:
                grouped[key] = {
                    "conversation": conversations.get(trace.conversation_id)
                    if trace.conversation_id
                    else None,
                    "traces": [],
                }
                order.append(key)
            grouped[key]["traces"].append(trace)
        groups = []
        for key in order:
            bucket = grouped[key]
            chronological = list(reversed(bucket["traces"]))
            groups.append(
                {
                    "conversation": bucket["conversation"],
                    "entries": _decorate(chronological),
                }
            )
        return user, groups


async def _search_users(q: str) -> list[User]:
    factory = get_session_factory()
    async with factory() as session:
        stmt = (
            select(User)
            .where(
                or_(
                    User.display_name.ilike(f"%{q}%"),
                    User.phone_masked.contains(q),
                )
            )
            .order_by(User.created_at.desc())
            .limit(20)
        )
        return list((await session.scalars(stmt)).all())


class LlmDebugView(BaseView):
    name = "模型调试"
    icon = "fa-solid fa-code-branch"
    category = "调试"

    @expose("/llm-debug", methods=["GET"])
    async def index(self, request: Request) -> Response:
        q = (request.query_params.get("q") or "").strip()
        users = await _search_users(q) if q else []
        return await self.templates.TemplateResponse(
            request,
            "sqladmin/llm_debug.html",
            {
                "q": q,
                "users": users,
                "user": None,
                "groups": [],
                "purpose": "",
                "status": "",
                "hours": "168",
                "purpose_options": PURPOSE_LABELS,
            },
        )

    @expose("/llm-debug/user/{user_id}", methods=["GET"])
    async def user_timeline(self, request: Request) -> Response:
        raw_id = request.path_params.get("user_id")
        try:
            user_id = UUID(str(raw_id))
        except ValueError:
            user_id = None
        purpose = (request.query_params.get("purpose") or "").strip()
        status = (request.query_params.get("status") or "").strip()
        try:
            hours = int(request.query_params.get("hours") or "168")
        except ValueError:
            hours = 168
        user = None
        groups: list[dict[str, Any]] = []
        if user_id is not None:
            user, groups = await _load_timeline(
                user_id=user_id,
                purpose=purpose or None,
                status=status or None,
                hours=hours,
            )
        return await self.templates.TemplateResponse(
            request,
            "sqladmin/llm_debug.html",
            {
                "q": "",
                "users": [],
                "user": user,
                "groups": groups,
                "purpose": purpose,
                "status": status,
                "hours": str(hours),
                "purpose_options": PURPOSE_LABELS,
            },
        )
