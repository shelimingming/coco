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
from coco.modules.voice.tools import dispatch_voice_tool


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
async def test_save_memory_tool_removed() -> None:
    settings = Settings(_env_file=None, environment="test")
    session = MagicMock()
    result = await dispatch_voice_tool(
        session=session,
        settings=settings,
        user=_parent(),
        name="save_memory",
        arguments={"content": "喜欢吃面", "category": "PREFERENCE"},
    )
    payload = json.loads(result)
    assert payload["status"] == "error"
    assert "未知工具" in payload["message"]


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
