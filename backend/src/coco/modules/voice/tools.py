"""Realtime Function Calling：工具 Schema 与分发。

提醒/分享写操作须带 user_confirmed；false 时不落库并返回 need_confirmation。
用户主动要求记住时用 save_memory 写入显式表；通话中可用 recall_memory 检索。
时效问答用 web_search（只读联网），不走确认大卡。
open_screen 只返回路由；由桥接层推 navigate.open，客户端跳转，不结束通话。
首页能力 pause_call / end_call / open_look_front / open_look_phone 只返回动作，
由桥接层推 home.action，客户端执行暂停、挂断或打开看眼前/看手机。
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
from coco.models.reminder import ReminderCreatedSource, ResponseSource, ResponseStatus
from coco.models.user import User
from coco.modules.care.schemas import CareShareCreateRequest
from coco.modules.care.service import CareService
from coco.modules.memories.service import MemoryService
from coco.modules.reminders.schemas import OccurrenceRespondRequest, ReminderCreateRequest
from coco.modules.reminders.service import ReminderService
from coco.providers.qwen_text import search_or_unavailable

logger = logging.getLogger(__name__)

# 父母端可语音打开的页面：screen → (route, 口语标签)
OPEN_SCREEN_ROUTES: dict[str, tuple[str, str]] = {
    "reminders": ("/parent/reminders", "提醒事项"),
    "memories": ("/parent/memories", "备忘录"),
    "daily_notes": ("/parent/daily-notes", "每日小记"),
    "history": ("/parent/history", "历史对话"),
    "settings": ("/parent/settings", "我的"),
    "functions": ("/parent/functions", "更多功能"),
    "home": ("/parent", "首页"),
}

# 首页能力：桥接层推 home.action，由客户端执行
HOME_VOICE_ACTIONS = frozenset(
    {"pause_call", "end_call", "open_look_front", "open_look_phone"}
)

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
                "仅当用户主动要求记住时调用（帮我记住、记一下、别忘了、记下来）。"
                "闲聊里的习惯/口味交给通话后自动整理，不要偷偷保存。"
                "已知记忆已有近似内容时不要重复调用。"
                "临时安排、药量、诊断、验证码不要记。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "content": {
                        "type": "string",
                        "description": "要记住的短陈述句，一两句即可",
                    },
                    "category": {
                        "type": "string",
                        "enum": ["PROFILE", "FAMILY", "PREFERENCE", "ROUTINE"],
                        "description": (
                            "PROFILE 关于我；FAMILY 家人；PREFERENCE 喜好；ROUTINE 日常习惯"
                        ),
                    },
                },
                "required": ["content", "category"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "recall_memory",
            "description": (
                "按需检索用户长期记忆。开场已知记忆不够用、需要回忆具体偏好/家人/习惯细节时调用；"
                "不要告知用户正在查记忆；不要用它来保存新事实。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "要回忆的主题，如「饮食忌口」「家人称呼」",
                    },
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "web_search",
            "description": (
                "联网查询实时信息：天气、新闻、时间敏感常识等。"
                "闲聊回忆、提醒、记忆、看图不要用；不要编造，必须等工具结果再口头回答。"
                "查到的天气/新闻只口述，不要因此追问或分享给家人。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "自然语言检索句，如「北京今天天气」「今天国内主要新闻」",
                    },
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "share_to_child",
            "description": (
                "把一两句关怀摘要分享给已绑定子女。仅在陪伴追问后关键事实已清楚、"
                "且老人同意（或主动要求）告诉家人时调用；不要刚听到不舒服就调用。"
                "summary 写给子女看：发生了什么、现在怎样、建议怎么做；不要聊天原文、不要诊断。"
                "先以 user_confirmed=false 弹出确认卡；点「告诉家人」或口头说好/对后再 true。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "summary": {
                        "type": "string",
                        "description": (
                            "给子女的一两句摘要，如："
                            "今天腿有些酸，目前还能正常走。你有空问候一下就好。"
                        ),
                    },
                    "urgency": {
                        "type": "string",
                        "enum": ["LOW", "ATTENTION"],
                        "description": "平稳问候用 LOW；摔倒、就医或希望尽快联系用 ATTENTION",
                    },
                    "user_confirmed": {
                        "type": "boolean",
                        "description": "用户是否已点卡或口头确认；未确认必须为 false",
                    },
                },
                "required": ["summary", "user_confirmed"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "re_vision_image",
            "description": (
                "当前照片上下文不够回答用户问题时，用原图再看一遍。"
                "适用于小字、日期、局部细节、包装说明等。"
                "question 填用户原话。每个问题最多调用一次；常识题不要调用。"
                "没有正在看的照片时不要调用。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "question": {
                        "type": "string",
                        "description": "用户想从照片里知道的问题，尽量用原话",
                    },
                },
                "required": ["question"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "close_vision_image",
            "description": (
                "用户说关掉照片、不用看了、看完了时调用。只结束看图，不要结束语音陪伴。"
            ),
            "parameters": {
                "type": "object",
                "properties": {},
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "stop_screen_share",
            "description": (
                "停止「看手机」投屏：用户说不用看了/关掉屏幕，或画面是支付、转账、验证码、"
                "密码、银行卡、身份凭证页时调用。只停投屏，不要结束语音陪伴。"
                "reason 用一句老人能听懂的话说明为什么停。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "reason": {
                        "type": "string",
                        "description": "停看原因，口语短句",
                    },
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "pause_call",
            "description": (
                "暂停当前语音陪伴：停收音，保留会话，不挂断。"
                "用户说暂停一下、先停停、等一会儿、我去忙、先不说了（但没说再见/挂了）时调用。"
                "不要用于结束聊天；不要在闲聊中途擅自暂停。"
            ),
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "end_call",
            "description": (
                "结束并挂断当前语音陪伴。"
                "仅当用户明确说不聊了、挂了、再见、结束聊天、关掉电话时调用。"
                "先调用本工具，再用一两句告别；客户端会在你说完后挂断。不要连环挽留。"
            ),
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "open_look_front",
            "description": (
                "打开「看眼前」：拉起相机拍眼前实物（药盒、报纸、手里的东西）。"
                "用户说看看这个、打开摄像头、拍一下、看眼前、帮我看看手里/桌上是什么时调用。"
                "看手机屏幕、短信、微信页面不要用本工具，改用 open_look_phone。"
                "已经在看照片时用户只是追问，不要再打开相机。"
            ),
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "open_look_phone",
            "description": (
                "打开「看手机」投屏：让可可看短信、微信或其它 App 画面。"
                "用户说看屏幕、看手机、看看这条短信、这个页面怎么点时调用。"
                "不要与 open_screen 混淆：open_screen 是打开可可 App 里的列表页。"
                "已经在看手机时不要再调用；用户说关掉才用 stop_screen_share。"
            ),
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "open_screen",
            "description": (
                "打开 App 内某个页面，方便老人用眼睛看列表或设置。"
                "用户说「打开提醒」「看看备忘录」「每日小记」「历史对话」「我的/设置」「更多功能」"
                "或「回首页」时调用。能直接用其他工具办的事（创建提醒、记住、分享）不要用本工具。"
                "打开页面后语音继续，不要挂断。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "screen": {
                        "type": "string",
                        "enum": list(OPEN_SCREEN_ROUTES.keys()),
                        "description": (
                            "reminders 提醒；memories 备忘录；daily_notes 每日小记；"
                            "history 历史对话；settings 我的/设置；functions 更多功能；home 首页"
                        ),
                    },
                },
                "required": ["screen"],
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
                occurrence_id = target.id
            else:
                occurrence_id = UUID(str(occurrence_id_raw))
            result = await reminder_service.respond_to_occurrence(
                session,
                user=user,
                occurrence_id=occurrence_id,
                body=OccurrenceRespondRequest(
                    status=ResponseStatus.COMPLETED_SELF_REPORTED.value,
                    source=ResponseSource.VOICE.value,
                ),
                user_confirmed=user_confirmed,
            )
            return _serialize(result)

        if name == "save_memory":
            result = await MemoryService().create_from_voice(
                session,
                user=user,
                content=str(arguments.get("content", "")),
                category=str(arguments.get("category", "")),
            )
            return _serialize(
                {
                    "status": "ok",
                    "id": result.id,
                    "content": result.content,
                    "category": result.category,
                }
            )

        if name == "recall_memory":
            query = str(arguments.get("query", "")).strip()
            items = await MemoryService().search_for_user(
                session,
                user=user,
                query=query,
            )
            return _serialize(
                {
                    "status": "ok",
                    "query": query,
                    "memories": [{"id": m.id, "content": m.content} for m in items],
                }
            )

        if name == "web_search":
            # A0 只读：服务端 enable_search 取数，Realtime 再口语播报
            query = str(arguments.get("query", "")).strip()
            result = await search_or_unavailable(
                api_key=settings.aliyun_api_key,
                model=settings.text_model,
                query=query,
                enabled=settings.web_search_enabled,
                base_url=settings.aliyun_compatible_base_url,
                timeout_seconds=settings.web_search_timeout_seconds,
            )
            if result.status == "ok":
                return _serialize(
                    {
                        "status": "ok",
                        "query": result.query,
                        "answer": result.answer,
                    }
                )
            return _serialize(
                {
                    "status": "error",
                    "query": result.query,
                    "message": result.message or "刚才联网没查到，您可以过会儿再问。",
                }
            )

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

        if name == "pause_call":
            return _serialize(
                {
                    "status": "ok",
                    "action": "pause_call",
                    "message": (
                        "已请客户端暂停收音、保留通话。"
                        "请只说一句：好，先暂停，想聊了再点继续聊天。不要挂断。"
                    ),
                }
            )

        if name == "end_call":
            return _serialize(
                {
                    "status": "ok",
                    "action": "end_call",
                    "message": (
                        "已请客户端在你说完后挂断。"
                        "请只用一两句告别，不要挽留，不要再问还聊不聊。"
                    ),
                }
            )

        if name == "open_look_front":
            return _serialize(
                {
                    "status": "ok",
                    "action": "open_look_front",
                    "message": (
                        "已请客户端打开相机看眼前。"
                        "请只说一句：好，请把要看的东西对着相机。不要挂断。"
                    ),
                }
            )

        if name == "open_look_phone":
            return _serialize(
                {
                    "status": "ok",
                    "action": "open_look_phone",
                    "message": (
                        "已请客户端打开看手机投屏。"
                        "请只说一句：好，按提示打开看手机，然后去打开要看的页面。不要挂断。"
                    ),
                }
            )

        if name == "open_screen":
            # A0：只解析路由；客户端跳转由桥接层推 navigate.open
            screen = str(arguments.get("screen", "")).strip()
            mapped = OPEN_SCREEN_ROUTES.get(screen)
            if mapped is None:
                return _serialize(
                    {
                        "status": "error",
                        "message": (
                            "没有这个页面。可以说打开提醒、备忘录、每日小记、"
                            "历史对话、我的，或更多功能。"
                        ),
                    }
                )
            route, label = mapped
            return _serialize(
                {
                    "status": "ok",
                    "screen": screen,
                    "route": route,
                    "label": label,
                    "message": f"已打开「{label}」，请继续陪用户说话，不要挂断。",
                }
            )

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
