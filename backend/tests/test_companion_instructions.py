"""陪伴系统提示：姓名与记忆开场注入。"""

from __future__ import annotations

from coco.modules.voice.prompts import (
    COCO_REALTIME_COMPANION_PROMPT,
    build_companion_instructions,
)


def test_empty_memories() -> None:
    text = build_companion_instructions([])
    assert COCO_REALTIME_COMPANION_PROMPT in text
    assert "暂无已存记忆" in text
    assert "姓名未知" in text
    assert "必须先调用 save_memory" in text
    assert "不可只聊天不存" in text
    assert "不要询问「要记住吗？」" in text
    # 提醒/分享：先出卡，点一下或说好，禁止连环追问
    assert "user_confirmed=false" in text
    assert "确认大卡" in text
    assert "禁止连环追问" in text


def test_injects_user_name() -> None:
    text = build_companion_instructions([], user_name="王奶奶")
    assert "姓名「王奶奶」" in text
    assert "偶尔自然称呼" in text


def test_injects_memories() -> None:
    text = build_companion_instructions(
        ["喜欢晚饭后散步", "女儿叫小林"],
        user_name="李叔叔",
    )
    assert "姓名「李叔叔」" in text
    assert "喜欢晚饭后散步" in text
    assert "女儿叫小林" in text
    assert "已知用户记忆" in text


def test_injects_look_context() -> None:
    text = build_companion_instructions(
        [],
        user_name="王奶奶",
        look_context="保质期到 2026年8月18日。今天还没有过期。",
    )
    assert "刚才帮用户看过一张图" in text
    assert "保质期到 2026年8月18日" in text
    assert "不要调用 save_memory 保存图中内容" in text


def test_truncates_by_count_and_chars() -> None:
    many = [f"记忆条目{i:04d}" + ("x" * 80) for i in range(50)]
    text = build_companion_instructions(many, user_name="测试")
    # 不应把 50 条全塞进去
    assert text.count("- 记忆条目") <= 30
    memory_section = text.split("已知用户记忆", 1)[1]
    assert len(memory_section) < 2000
