"""列表/详情把 UUID 外键渲染成可读名称（用户名、家庭、提醒标题）。"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any
from uuid import UUID

from coco.models.conversation import Conversation
from coco.models.family import Family
from coco.models.reminder import Reminder
from coco.models.user import User
from markupsafe import Markup, escape
from sqlalchemy import select
from starlette.requests import Request

from coco_admin.database import get_session_factory


@dataclass
class AdminLabelMaps:
    users: dict[UUID, str] = field(default_factory=dict)
    families: dict[UUID, str] = field(default_factory=dict)
    reminders: dict[UUID, str] = field(default_factory=dict)
    conversations: dict[UUID, str] = field(default_factory=dict)


def labels_from_request(request: Request | None) -> AdminLabelMaps:
    if request is None:
        return AdminLabelMaps()
    maps = getattr(request.state, "admin_labels", None)
    return maps if isinstance(maps, AdminLabelMaps) else AdminLabelMaps()


def _collect_uuids(rows: list[Any], attrs: tuple[str, ...]) -> set[UUID]:
    ids: set[UUID] = set()
    for row in rows:
        for attr in attrs:
            value = getattr(row, attr, None)
            if isinstance(value, UUID):
                ids.add(value)
    return ids


async def warm_admin_labels(
    request: Request,
    rows: list[Any],
    *,
    user_attrs: tuple[str, ...] = (),
    family_attrs: tuple[str, ...] = (),
    reminder_attrs: tuple[str, ...] = (),
    conversation_attrs: tuple[str, ...] = (),
) -> AdminLabelMaps:
    """按当前页行预加载可读标签，供 column_formatters 同步读取。"""
    user_ids = _collect_uuids(rows, user_attrs)
    family_ids = _collect_uuids(rows, family_attrs)
    reminder_ids = _collect_uuids(rows, reminder_attrs)
    conversation_ids = _collect_uuids(rows, conversation_attrs)

    maps = AdminLabelMaps()
    if not user_ids and not family_ids and not reminder_ids and not conversation_ids:
        request.state.admin_labels = maps
        return maps

    factory = get_session_factory()
    async with factory() as session:
        if conversation_ids:
            conversations = (
                await session.scalars(
                    select(Conversation).where(Conversation.id.in_(conversation_ids))
                )
            ).all()
            for conv in conversations:
                user_ids.add(conv.user_id)

        if family_ids:
            families = (
                await session.scalars(select(Family).where(Family.id.in_(family_ids)))
            ).all()
            for fam in families:
                user_ids.add(fam.parent_user_id)
                if fam.child_user_id is not None:
                    user_ids.add(fam.child_user_id)

        if user_ids:
            users = (await session.scalars(select(User).where(User.id.in_(user_ids)))).all()
            maps.users = {u.id: u.display_name for u in users}

        if family_ids:
            families = (
                await session.scalars(select(Family).where(Family.id.in_(family_ids)))
            ).all()
            for fam in families:
                parent = maps.users.get(fam.parent_user_id, "未知父母")
                if fam.child_user_id is None:
                    maps.families[fam.id] = f"{parent} · 待加入"
                else:
                    child = maps.users.get(fam.child_user_id, "未知子女")
                    maps.families[fam.id] = f"{parent} ↔ {child}"

        if reminder_ids:
            reminders = (
                await session.scalars(select(Reminder).where(Reminder.id.in_(reminder_ids)))
            ).all()
            maps.reminders = {r.id: r.title for r in reminders}

        if conversation_ids:
            conversations = (
                await session.scalars(
                    select(Conversation).where(Conversation.id.in_(conversation_ids))
                )
            ).all()
            for conv in conversations:
                owner = maps.users.get(conv.user_id, "未知用户")
                started = conv.started_at.strftime("%m-%d %H:%M") if conv.started_at else "?"
                maps.conversations[conv.id] = f"{owner} · {started}"

    request.state.admin_labels = maps
    return maps


def format_user_name(model: Any, attr: str, request: Request | None = None) -> str:
    uid = getattr(model, attr, None)
    if uid is None:
        return "—"
    name = labels_from_request(request).users.get(uid)
    return name or "未知用户"


def format_user_name_detail(model: Any, attr: str, request: Request | None = None) -> Markup:
    """详情：可读名为主，UUID 次之便于排查。"""
    uid = getattr(model, attr, None)
    if uid is None:
        return Markup("—")
    name = escape(format_user_name(model, attr, request))
    return Markup(f"{name}<br><code class='text-secondary'>{escape(str(uid))}</code>")


def format_family_label(model: Any, attr: str, request: Request | None = None) -> str:
    fid = getattr(model, attr, None)
    if fid is None:
        return "—"
    return labels_from_request(request).families.get(fid) or "未知家庭"


def format_family_label_detail(model: Any, attr: str, request: Request | None = None) -> Markup:
    fid = getattr(model, attr, None)
    if fid is None:
        return Markup("—")
    label = escape(format_family_label(model, attr, request))
    return Markup(f"{label}<br><code class='text-secondary'>{escape(str(fid))}</code>")


def format_reminder_title(model: Any, attr: str, request: Request | None = None) -> str:
    rid = getattr(model, attr, None)
    if rid is None:
        return "—"
    return labels_from_request(request).reminders.get(rid) or "未知提醒"


def format_reminder_title_detail(model: Any, attr: str, request: Request | None = None) -> Markup:
    rid = getattr(model, attr, None)
    if rid is None:
        return Markup("—")
    title = escape(format_reminder_title(model, attr, request))
    return Markup(f"{title}<br><code class='text-secondary'>{escape(str(rid))}</code>")


def format_conversation_label(model: Any, attr: str, request: Request | None = None) -> str:
    cid = getattr(model, attr, None)
    if cid is None:
        return "—"
    return labels_from_request(request).conversations.get(cid) or "未知会话"


def format_conversation_label_detail(
    model: Any, attr: str, request: Request | None = None
) -> Markup:
    cid = getattr(model, attr, None)
    if cid is None:
        return Markup("—")
    label = escape(format_conversation_label(model, attr, request))
    return Markup(f"{label}<br><code class='text-secondary'>{escape(str(cid))}</code>")
