"""工具调用白话摘要单测。"""

from __future__ import annotations

from coco.models.conversation import ConversationItemKind
from coco.modules.conversations.service import should_list_in_history, tool_display_summary


def test_save_memory_summary_compat() -> None:
    # 新通话不再落库记忆工具；兼容历史数据的展示文案
    assert (
        tool_display_summary(
            "save_memory",
            {"content": "喜欢晚饭后散步"},
            {"id": "x", "content": "喜欢晚饭后散步"},
        )
        == "帮你记住：喜欢晚饭后散步"
    )


def test_create_reminder_and_list() -> None:
    assert (
        tool_display_summary(
            "create_reminder",
            {"title": "吃药"},
            {"title": "吃药"},
        )
        == "帮你设了提醒：吃药"
    )
    assert tool_display_summary("list_reminders", {}, {}) == "可可查看了你的提醒"
    assert tool_display_summary("list_memories", {}, {}) == "可可查看了你记住的事"


def test_should_list_in_history_filters_greeting_only() -> None:
    class _Item:
        def __init__(self, kind: str, text: str | None = None) -> None:
            self.kind = kind
            self.text = text

    assert not should_list_in_history([])
    assert not should_list_in_history(
        [_Item(ConversationItemKind.ASSISTANT.value, "余黎明，深夜我在呢。")]
    )
    assert not should_list_in_history(
        [
            _Item(ConversationItemKind.ASSISTANT.value, "晚上好，我在这儿呢。"),
            _Item(ConversationItemKind.ASSISTANT.value, "有什么想聊的吗？"),
        ]
    )
    assert should_list_in_history(
        [
            _Item(ConversationItemKind.ASSISTANT.value, "晚上好。"),
            _Item(ConversationItemKind.USER.value, "嗯"),
        ]
    )
    assert should_list_in_history(
        [
            _Item(ConversationItemKind.TOOL.value),
        ]
    )


def test_share_to_child_summary() -> None:
    assert (
        tool_display_summary(
            "share_to_child",
            {"summary": "今天精神不错"},
            {"status": "need_confirmation"},
        )
        == "还在问你要不要告诉家人：今天精神不错"
    )


def test_web_search_summary() -> None:
    assert tool_display_summary("web_search", {"query": "北京天气"}, {"status": "ok"}) == (
        "可可查了网上的消息"
    )
    assert tool_display_summary("web_search", {"query": "新闻"}, {"status": "error"}) == (
        "可可没查到网上的消息"
    )
