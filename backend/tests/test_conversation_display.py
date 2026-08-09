"""工具调用白话摘要单测。"""

from __future__ import annotations

from coco.modules.conversations.service import tool_display_summary


def test_save_memory_summaries() -> None:
    assert (
        tool_display_summary(
            "save_memory",
            {"content": "喜欢晚饭后散步"},
            {"status": "need_confirmation", "content": "喜欢晚饭后散步"},
        )
        == "还在问你要不要记住：喜欢晚饭后散步"
    )
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


def test_share_to_child_summary() -> None:
    assert (
        tool_display_summary(
            "share_to_child",
            {"summary": "今天精神不错"},
            {"status": "need_confirmation"},
        )
        == "还在问你要不要告诉家人：今天精神不错"
    )
