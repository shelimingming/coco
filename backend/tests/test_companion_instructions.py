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
    assert "尚未绑定子女" in text
    assert "不可承诺已经通知家人" in text
    assert "自动整理" in text
    assert "recall_memory" in text
    assert "不要询问「要记住吗？」" in text
    # 提醒：先出卡；关怀：先追问再汇总，同意后才出分享卡
    assert "user_confirmed=false" in text
    assert "确认大卡" in text
    assert "禁止连环追问" in text
    assert "先陪伴" in text
    assert "有限追问" in text
    assert "未经老人同意，禁止分享" in text
    assert "刚听到不舒服就调用 share_to_child" in text
    assert "你有空问候一下就好" in text


def test_injects_user_name() -> None:
    text = build_companion_instructions([], user_name="王奶奶")
    assert "姓名「王奶奶」" in text
    assert "偶尔自然称呼" in text
    assert "尚未绑定子女" in text


def test_injects_bound_child_name() -> None:
    text = build_companion_instructions(
        [],
        user_name="王奶奶",
        child_name="小林",
    )
    assert "已绑定子女：姓名「小林」" in text
    assert "尚未绑定子女" not in text
    assert "勿编造其他子女姓名" in text
    assert "主动问要不要告诉「小林」" in text


def test_bound_child_without_name_falls_back() -> None:
    # 已绑定但昵称为空时，用「家人」兜底，仍标明已绑定
    text = build_companion_instructions([], child_name="")
    assert "已绑定子女：姓名「家人」" in text


def test_injects_memories() -> None:
    text = build_companion_instructions(
        ["喜欢晚饭后散步", "女儿叫小林"],
        user_name="李叔叔",
        child_name="小林",
    )
    assert "姓名「李叔叔」" in text
    assert "已绑定子女：姓名「小林」" in text
    assert "喜欢晚饭后散步" in text
    assert "女儿叫小林" in text
    assert "已知用户记忆" in text


def test_truncates_by_count_and_chars() -> None:
    many = [f"记忆条目{i:04d}" + ("x" * 80) for i in range(50)]
    text = build_companion_instructions(many, user_name="测试")
    # 不应把 50 条全塞进去
    assert text.count("- 记忆条目") <= 30
    memory_section = text.split("已知用户记忆", 1)[1]
    assert len(memory_section) < 2000


def test_vision_context_block_and_merge() -> None:
    from coco.modules.voice.prompts import (
        VISION_INJECT_TRIGGER_TEXT,
        build_vision_context_block,
        merge_instructions_with_vision,
    )

    block = build_vision_context_block(
        "一张红烧肉照片，盘子在桌上。",
        source="album",
    )
    assert "当前照片上下文" in block
    assert "相册照片" in block
    assert "红烧肉" in block
    assert "不要记入长期记忆" in block
    assert "按关怀对话规则先陪伴追问" in block

    base = build_companion_instructions([], user_name="王奶奶")
    merged = merge_instructions_with_vision(base, "药盒标签写着阿司匹林", source="camera")
    assert "王奶奶" in merged
    assert "眼前实拍" in merged
    assert "阿司匹林" in merged
    # 换图：再 merge 仍以 base 为底，不累加旧照片块
    merged2 = merge_instructions_with_vision(base, "一盆绿植", source="camera")
    assert "绿植" in merged2
    assert "阿司匹林" not in merged2
    assert "系统：用户刚把一张照片" in VISION_INJECT_TRIGGER_TEXT
