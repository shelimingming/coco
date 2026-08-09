"""Realtime Function Calling：工具 Schema 与分发。

提醒/分享写操作须带 user_confirmed；false 时不落库并返回 need_confirmation。
记忆由语音侧静默写入，不经用户口头确认；读记忆在开场注入系统提示，无 list 工具。
"""

from __future__ import annotations

import json
import logging
from datetime import time
from typing import Any
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from coco.config import Settings
from coco.errors import AppError
from coco.models.care import CareSource
from coco.models.memory import MemorySource
from coco.models.reminder import ReminderCreatedSource
from coco.models.user import User
from coco.modules.care.schemas import CareShareCreateRequest
from coco.modules.care.service import CareService
from coco.modules.memories.schemas import MemoryCreateRequest
from coco.modules.memories.service import MemoryService
from coco.modules.reminders.schemas import ReminderCreateRequest
from coco.modules.reminders.service import ReminderService

logger = logging.getLogger(__name__)

# 百炼 session.update 所需的 tools 定义
VOICE_TOOL_DEFINITIONS: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "create_reminder",
            "description": (
                "为老人创建日常提醒。参数齐全后先以 user_confirmed=false 弹出确认卡；"
                "用户点卡或口头说好/对后，再以 user_confirmed=true 调用。勿在 false 前连环追问。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "title": {"type": "string", "description": "提醒内容，如吃药"},
                    "schedule_type": {
                        "type": "string",
                        "enum": ["ONCE", "DAILY"],
                        "description": "ONCE 仅一次，DAILY 每天",
                    },
                    "schedule_time": {
                        "type": "string",
                        "description": "本地时刻 HH:MM，如 20:00",
                    },
                    "user_confirmed": {
                        "type": "boolean",
                        "description": "用户是否已点卡或口头确认；未确认必须为 false",
                    },
                },
                "required": ["title", "schedule_type", "schedule_time", "user_confirmed"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "list_reminders",
            "description": "查询老人当前有效的提醒列表。",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "confirm_reminder",
            "description": ("确认某条到点提醒已完成。未口头确认时 user_confirmed=false。"),
            "parameters": {
                "type": "object",
                "properties": {
                    "reminder_id": {"type": "string"},
                    "occurrence_id": {"type": "string"},
                    "user_confirmed": {"type": "boolean"},
                },
                "required": ["user_confirmed"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "save_memory",
            "description": (
                "静默保存用户的稳定偏好/习惯/家人信息。用户说出喜好饮食、自己做饭、作息、家人称呼等时必须调用；"
                "不要告知用户；已知记忆里已有近似内容时不要重复调用。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "content": {"type": "string"},
                    "category": {
                        "type": "string",
                        "enum": ["PROFILE", "FAMILY", "PREFERENCE", "ROUTINE"],
                    },
                },
                "required": ["content", "category"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "share_to_child",
            "description": (
                "把关怀摘要分享给已绑定的子女。摘要齐全后先以 user_confirmed=false 弹出确认卡；"
                "用户点「告诉家人」或口头说好/对之后，再以 user_confirmed=true 调用。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "summary": {"type": "string"},
                    "urgency": {"type": "string", "enum": ["LOW", "ATTENTION"]},
                    "user_confirmed": {
                        "type": "boolean",
                        "description": "用户是否已点卡或口头确认；未确认必须为 false",
                    },
                },
                "required": ["summary", "user_confirmed"],
            },
        },
    },
]


def _parse_time(value: str) -> time:
    parts = value.strip().split(":")
    if len(parts) < 2:
        raise AppError(400, "voice.invalid_time", "时间格式不对，请用类似晚上八点这样说。")
    hour = int(parts[0])
    minute = int(parts[1])
    return time(hour=hour, minute=minute)


def _serialize(value: Any) -> str:
    if hasattr(value, "model_dump"):
        return json.dumps(value.model_dump(mode="json"), ensure_ascii=False)
    if isinstance(value, list):
        return json.dumps(
            [v.model_dump(mode="json") if hasattr(v, "model_dump") else v for v in value],
            ensure_ascii=False,
        )
    return json.dumps(value, ensure_ascii=False, default=str)


async def dispatch_voice_tool(
    *,
    session: AsyncSession,
    settings: Settings,
    user: User,
    name: str,
    arguments: dict[str, Any],
) -> str:
    """执行工具并返回写回供应商的 JSON 字符串。"""
    try:
        if name == "create_reminder":
            body = ReminderCreateRequest(
                title=str(arguments.get("title", "")),
                schedule_type=str(arguments.get("schedule_type", "ONCE")),
                schedule_time=_parse_time(str(arguments.get("schedule_time", "09:00"))),
                user_confirmed=bool(arguments.get("user_confirmed", False)),
            )
            result = await ReminderService(settings).create(
                session,
                user=user,
                body=body,
                created_source=ReminderCreatedSource.VOICE.value,
            )
            return _serialize(result)

        if name == "list_reminders":
            result = await ReminderService(settings).list_for_user(session, user=user)
            return _serialize(result)

        if name == "confirm_reminder":
            reminder_service = ReminderService(settings)
            reminder_id_raw = arguments.get("reminder_id")
            occurrence_id_raw = arguments.get("occurrence_id")
            user_confirmed = bool(arguments.get("user_confirmed", False))
            # 若未指定 id，尝试匹配最近一条开放 occurrence
            if not reminder_id_raw or not occurrence_id_raw:
                open_items = await reminder_service.list_open_occurrences(session, user=user)
                if not open_items:
                    return _serialize(
                        {
                            "status": "error",
                            "message": "当前没有需要确认的提醒。",
                        }
                    )
                target = open_items[0]
                reminder_id = target.reminder_id
                occurrence_id = target.id
            else:
                reminder_id = UUID(str(reminder_id_raw))
                occurrence_id = UUID(str(occurrence_id_raw))
            result = await reminder_service.confirm_occurrence(
                session,
                user=user,
                reminder_id=reminder_id,
                occurrence_id=occurrence_id,
                user_confirmed=user_confirmed,
            )
            return _serialize(result)

        if name == "save_memory":
            # 语音侧自动写入：不依赖模型传 user_confirmed
            body = MemoryCreateRequest(
                content=str(arguments.get("content", "")),
                category=str(arguments.get("category", "PREFERENCE")),
                user_confirmed=True,
            )
            result = await MemoryService().create(
                session,
                user=user,
                body=body,
                source=MemorySource.VOICE.value,
            )
            return _serialize(result)

        if name == "share_to_child":
            body = CareShareCreateRequest(
                summary=str(arguments.get("summary", "")),
                urgency=str(arguments.get("urgency", "LOW")),
                user_confirmed=bool(arguments.get("user_confirmed", False)),
            )
            result = await CareService(settings).create_share(
                session,
                user=user,
                body=body,
                source=CareSource.VOICE.value,
            )
            return _serialize(result)

        return _serialize({"status": "error", "message": f"未知工具: {name}"})
    except AppError as exc:
        return _serialize({"status": "error", "code": exc.code, "message": exc.message})
    except Exception:
        logger.exception("voice_tool_failed name=%s", name)
        return _serialize(
            {
                "status": "error",
                "message": "刚才没办成。您可以再说一次，数据没有错误写入。",
            }
        )
