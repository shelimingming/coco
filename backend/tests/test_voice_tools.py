"""语音工具：提醒须确认；记忆按需检索。"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

from coco.config import Settings
from coco.models.user import User, UserRole, UserStatus
from coco.modules.memories.schemas import MemoryResponse
from coco.modules.voice.tools import VOICE_TOOL_DEFINITIONS, dispatch_voice_tool
from coco.providers.qwen_text import WebSearchResult, search_or_unavailable


def _parent() -> User:
    return User(
        id=uuid4(),
        phone_hash="hash",
        phone_masked="138****0000",
        display_name="测试父母",
        role=UserRole.PARENT.value,
        status=UserStatus.ACTIVE.value,
    )


@pytest.mark.asyncio
async def test_create_reminder_needs_confirmation() -> None:
    settings = Settings(_env_file=None, environment="test")
    session = AsyncMock()
    result = await dispatch_voice_tool(
        session=session,
        settings=settings,
        user=_parent(),
        name="create_reminder",
        arguments={
            "title": "吃药",
            "schedule_type": "DAILY",
            "schedule_time": "20:00",
            "user_confirmed": False,
        },
    )
    payload = json.loads(result)
    assert payload["status"] == "need_confirmation"
    session.add.assert_not_called()


@pytest.mark.asyncio
async def test_recall_memory_searches() -> None:
    settings = Settings(_env_file=None, environment="test")
    session = MagicMock()
    now = datetime.now(UTC)
    parent = _parent()

    with patch("coco.modules.voice.tools.MemoryService") as svc_cls:
        svc = svc_cls.return_value
        svc.search_for_user = AsyncMock(
            return_value=[
                MemoryResponse(
                    id="mem-1",
                    content="喜欢晚饭后散步",
                    created_at=now,
                    updated_at=now,
                )
            ]
        )
        result = await dispatch_voice_tool(
            session=session,
            settings=settings,
            user=parent,
            name="recall_memory",
            arguments={"query": "散步习惯"},
        )

    payload = json.loads(result)
    assert payload["status"] == "ok"
    assert payload["query"] == "散步习惯"
    assert payload["memories"][0]["content"] == "喜欢晚饭后散步"
    svc.search_for_user.assert_awaited_once()


@pytest.mark.asyncio
async def test_save_memory_persists() -> None:
    settings = Settings(_env_file=None, environment="test")
    session = MagicMock()
    parent = _parent()
    now = datetime.now(UTC)

    with patch("coco.modules.voice.tools.MemoryService") as svc_cls:
        svc = svc_cls.return_value
        svc.create_from_voice = AsyncMock(
            return_value=MemoryResponse(
                id="mem-new",
                content="喜欢吃面",
                category="PREFERENCE",
                source="VOICE",
                created_at=now,
                updated_at=now,
            )
        )
        result = await dispatch_voice_tool(
            session=session,
            settings=settings,
            user=parent,
            name="save_memory",
            arguments={"content": "喜欢吃面", "category": "PREFERENCE"},
        )

    payload = json.loads(result)
    assert payload["status"] == "ok"
    assert payload["content"] == "喜欢吃面"
    assert payload["category"] == "PREFERENCE"
    svc.create_from_voice.assert_awaited_once()


@pytest.mark.asyncio
async def test_list_memories_tool_removed() -> None:
    settings = Settings(_env_file=None, environment="test")
    session = MagicMock()
    result = await dispatch_voice_tool(
        session=session,
        settings=settings,
        user=_parent(),
        name="list_memories",
        arguments={},
    )
    payload = json.loads(result)
    assert payload["status"] == "error"
    assert "未知工具" in payload["message"]


@pytest.mark.asyncio
async def test_unknown_tool_returns_error() -> None:
    settings = Settings(_env_file=None, environment="test")
    session = MagicMock()
    result = await dispatch_voice_tool(
        session=session,
        settings=settings,
        user=_parent(),
        name="fly_to_moon",
        arguments={},
    )
    payload = json.loads(result)
    assert payload["status"] == "error"



@pytest.mark.asyncio
async def test_web_search_ok() -> None:
    settings = Settings(_env_file=None, environment="test")
    session = MagicMock()
    parent = _parent()

    with patch("coco.modules.voice.tools.search_or_unavailable", new_callable=AsyncMock) as search:
        search.return_value = WebSearchResult(
            status="ok",
            query="北京今天天气",
            answer="今天北京多云，大约二十度。",
        )
        result = await dispatch_voice_tool(
            session=session,
            settings=settings,
            user=parent,
            name="web_search",
            arguments={"query": "北京今天天气"},
        )

    payload = json.loads(result)
    assert payload["status"] == "ok"
    assert payload["query"] == "北京今天天气"
    assert "二十度" in payload["answer"]
    search.assert_awaited_once()


@pytest.mark.asyncio
async def test_web_search_error_degrades() -> None:
    settings = Settings(_env_file=None, environment="test", web_search_enabled=False)
    session = MagicMock()

    with patch("coco.modules.voice.tools.search_or_unavailable", new_callable=AsyncMock) as search:
        search.return_value = WebSearchResult(
            status="error",
            query="今天新闻",
            message="暂时查不了网上的消息，您可以过会儿再问。",
        )
        result = await dispatch_voice_tool(
            session=session,
            settings=settings,
            user=_parent(),
            name="web_search",
            arguments={"query": "今天新闻"},
        )

    payload = json.loads(result)
    assert payload["status"] == "error"
    assert "查不了" in payload["message"] or "没查到" in payload["message"]


def test_web_search_tool_registered() -> None:
    names = [item["function"]["name"] for item in VOICE_TOOL_DEFINITIONS]
    assert "web_search" in names


@pytest.mark.asyncio
async def test_search_or_unavailable_when_disabled() -> None:
    result = await search_or_unavailable(
        api_key=None,
        model="qwen-plus",
        query="北京天气",
        enabled=False,
    )
    assert result.status == "error"
    assert result.query == "北京天气"
    assert "查不了" in result.message


def test_vision_tools_are_registered() -> None:
    names = [item["function"]["name"] for item in VOICE_TOOL_DEFINITIONS]
    assert "re_vision_image" in names
    assert "close_vision_image" in names


def test_open_screen_tool_registered() -> None:
    names = [item["function"]["name"] for item in VOICE_TOOL_DEFINITIONS]
    assert "open_screen" in names
    tool = next(item for item in VOICE_TOOL_DEFINITIONS if item["function"]["name"] == "open_screen")
    enum_vals = tool["function"]["parameters"]["properties"]["screen"]["enum"]
    assert "reminders" in enum_vals
    assert "home" in enum_vals


@pytest.mark.asyncio
async def test_open_screen_ok() -> None:
    settings = Settings(_env_file=None, environment="test")
    session = AsyncMock()
    result = await dispatch_voice_tool(
        session=session,
        settings=settings,
        user=_parent(),
        name="open_screen",
        arguments={"screen": "reminders"},
    )
    payload = json.loads(result)
    assert payload["status"] == "ok"
    assert payload["route"] == "/parent/reminders"
    assert payload["label"] == "提醒事项"
    session.add.assert_not_called()


@pytest.mark.asyncio
async def test_open_screen_unknown() -> None:
    settings = Settings(_env_file=None, environment="test")
    result = await dispatch_voice_tool(
        session=AsyncMock(),
        settings=settings,
        user=_parent(),
        name="open_screen",
        arguments={"screen": "admin"},
    )
    payload = json.loads(result)
    assert payload["status"] == "error"


def test_home_voice_actions_registered() -> None:
    names = [item["function"]["name"] for item in VOICE_TOOL_DEFINITIONS]
    assert "pause_call" in names
    assert "end_call" in names
    assert "open_look_front" in names
    assert "open_look_phone" in names


@pytest.mark.asyncio
async def test_home_voice_actions_dispatch() -> None:
    settings = Settings(_env_file=None, environment="test")
    session = AsyncMock()
    for name in ("pause_call", "end_call", "open_look_front", "open_look_phone"):
        result = await dispatch_voice_tool(
            session=session,
            settings=settings,
            user=_parent(),
            name=name,
            arguments={},
        )
        payload = json.loads(result)
        assert payload["status"] == "ok"
        assert payload["action"] == name
    session.add.assert_not_called()
