"""用户 / 家庭详情页的跨表聚合查询。"""

from __future__ import annotations

import uuid
from typing import Any

from coco.models.auth import AuthSession
from coco.models.care import CareShare, FamilyMessage
from coco.models.conversation import Conversation, ConversationItem
from coco.models.family import Family, FamilyInvite
from coco.models.memory import Memory
from coco.models.notification import Notification
from coco.models.reminder import Reminder
from coco.models.user import User
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession


async def load_user_aggregate(session: AsyncSession, user_id: uuid.UUID) -> dict[str, Any]:
    user = await session.get(User, user_id)
    if user is None:
        return {"user": None}

    families = (
        await session.scalars(
            select(Family).where(
                or_(Family.parent_user_id == user_id, Family.child_user_id == user_id)
            )
        )
    ).all()
    reminders = (
        await session.scalars(
            select(Reminder)
            .where(Reminder.user_id == user_id)
            .order_by(Reminder.created_at.desc())
            .limit(50)
        )
    ).all()
    memories = (
        await session.scalars(
            select(Memory)
            .where(Memory.user_id == user_id)
            .order_by(Memory.created_at.desc())
            .limit(50)
        )
    ).all()
    care_shares = (
        await session.scalars(
            select(CareShare)
            .where(or_(CareShare.parent_id == user_id, CareShare.child_id == user_id))
            .order_by(CareShare.created_at.desc())
            .limit(50)
        )
    ).all()
    messages = (
        await session.scalars(
            select(FamilyMessage)
            .where(
                or_(
                    FamilyMessage.from_user_id == user_id,
                    FamilyMessage.to_user_id == user_id,
                )
            )
            .order_by(FamilyMessage.created_at.desc())
            .limit(50)
        )
    ).all()
    notifications = (
        await session.scalars(
            select(Notification)
            .where(Notification.user_id == user_id)
            .order_by(Notification.created_at.desc())
            .limit(50)
        )
    ).all()
    sessions = (
        await session.scalars(
            select(AuthSession)
            .where(AuthSession.user_id == user_id)
            .order_by(AuthSession.created_at.desc())
            .limit(20)
        )
    ).all()
    conversations = (
        await session.scalars(
            select(Conversation)
            .where(Conversation.user_id == user_id)
            .order_by(Conversation.started_at.desc())
            .limit(30)
        )
    ).all()

    # 聚合表用展示名，避免详情里再铺一长串 UUID
    related_user_ids = {user_id}
    for fam in families:
        related_user_ids.add(fam.parent_user_id)
        if fam.child_user_id is not None:
            related_user_ids.add(fam.child_user_id)
    for care in care_shares:
        related_user_ids.add(care.parent_id)
        related_user_ids.add(care.child_id)
    for msg in messages:
        related_user_ids.add(msg.from_user_id)
        related_user_ids.add(msg.to_user_id)

    related_users = (await session.scalars(select(User).where(User.id.in_(related_user_ids)))).all()
    users_by_id = {u.id: u for u in related_users}

    return {
        "user": user,
        "users_by_id": users_by_id,
        "families": families,
        "reminders": reminders,
        "memories": memories,
        "care_shares": care_shares,
        "messages": messages,
        "notifications": notifications,
        "sessions": sessions,
        "conversations": conversations,
    }


async def load_conversation_aggregate(
    session: AsyncSession, conversation_id: uuid.UUID
) -> dict[str, Any]:
    """会话详情：用户名 + 按序号排列的转写/工具条目。"""
    conversation = await session.get(Conversation, conversation_id)
    if conversation is None:
        return {"conversation": None}

    user = await session.get(User, conversation.user_id)
    items = (
        await session.scalars(
            select(ConversationItem)
            .where(ConversationItem.conversation_id == conversation_id)
            .order_by(ConversationItem.seq.asc())
        )
    ).all()
    return {
        "conversation": conversation,
        "user": user,
        "items": items,
    }


async def load_family_aggregate(session: AsyncSession, family_id: uuid.UUID) -> dict[str, Any]:
    family = await session.get(Family, family_id)
    if family is None:
        return {"family": None}

    parent = await session.get(User, family.parent_user_id)
    child = (
        await session.get(User, family.child_user_id) if family.child_user_id is not None else None
    )
    invites = (
        await session.scalars(
            select(FamilyInvite)
            .where(FamilyInvite.family_id == family_id)
            .order_by(FamilyInvite.created_at.desc())
            .limit(50)
        )
    ).all()
    messages = (
        await session.scalars(
            select(FamilyMessage)
            .where(FamilyMessage.family_id == family_id)
            .order_by(FamilyMessage.created_at.desc())
            .limit(50)
        )
    ).all()

    care_shares: list[CareShare] = []
    if family.child_user_id is not None:
        care_shares = list(
            (
                await session.scalars(
                    select(CareShare)
                    .where(
                        CareShare.parent_id == family.parent_user_id,
                        CareShare.child_id == family.child_user_id,
                    )
                    .order_by(CareShare.created_at.desc())
                    .limit(50)
                )
            ).all()
        )

    return {
        "family": family,
        "parent": parent,
        "child": child,
        "invites": invites,
        "messages": messages,
        "care_shares": care_shares,
    }
