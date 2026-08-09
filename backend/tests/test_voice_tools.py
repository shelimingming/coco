"""语音工具 user_confirmed 拦截单测（不连库）。"""

from __future__ import annotations

import json
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from coco.config import Settings
from coco.models.user import User, UserRole, UserStatus
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
async def test_save_memory_needs_confirmation() -> None:
    settings = Settings(_env_file=None, environment="test")
    session = AsyncMock()
    result = await dispatch_voice_tool(
        session=session,
        settings=settings,
        user=_parent(),
        name="save_memory",
        arguments={
            "content": "喜欢晚饭后散步",
            "category": "PREFERENCE",
            "user_confirmed": False,
        },
    )
    payload = json.loads(result)
    assert payload["status"] == "need_confirmation"
    session.add.assert_not_called()


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
