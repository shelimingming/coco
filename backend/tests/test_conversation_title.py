"""会话结束标题生成：清洗、摘录与降级。"""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from coco.models.conversation import ConversationItemKind
from coco.modules.conversations.service import transcript_for_title
from coco.providers.qwen_text import (
    fallback_conversation_title,
    sanitize_conversation_title,
    title_or_fallback,
)


def test_sanitize_conversation_title() -> None:
    assert sanitize_conversation_title("「今天聊天气」") == "今天聊天气"
    assert sanitize_conversation_title("标题：打个招呼") == "打个招呼"
    assert len(sanitize_conversation_title("这是一个非常非常非常长的标题内容")) == 16


def test_fallback_conversation_title() -> None:
    assert fallback_conversation_title("") == "还没说上话"
    assert fallback_conversation_title("这次还没有记下说话内容") == "还没说上话"
    assert fallback_conversation_title("hello hello.") == "hello hello."


def test_transcript_for_title() -> None:
    items = [
        SimpleNamespace(kind=ConversationItemKind.USER.value, text="你好", display_summary=None),
        SimpleNamespace(
            kind=ConversationItemKind.ASSISTANT.value,
            text="您好呀",
            display_summary=None,
        ),
        SimpleNamespace(
            kind=ConversationItemKind.TOOL.value,
            text=None,
            display_summary="帮你记住：喜欢散步",
        ),
    ]
    text = transcript_for_title(items)  # type: ignore[arg-type]
    assert "用户：你好" in text
    assert "可可：您好呀" in text
    assert "帮你记住：喜欢散步" in text


@pytest.mark.asyncio
async def test_title_or_fallback_without_api_key() -> None:
    result = await title_or_fallback(
        api_key=None,
        model="qwen-plus",
        transcript="用户：hello\n可可：你好",
        preview="hello",
    )
    assert result.generated is False
    assert result.title == "hello"
