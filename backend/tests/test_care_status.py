"""子女今日状态规则单测。"""

from __future__ import annotations

from coco.modules.care.service import compute_child_today_status


def test_need_contact_when_escalated() -> None:
    assert (
        compute_child_today_status(has_escalated=True, has_attention_share=True) == "NEED_CONTACT"
    )


def test_attention_when_share_only() -> None:
    assert compute_child_today_status(has_escalated=False, has_attention_share=True) == "ATTENTION"


def test_normal_when_quiet() -> None:
    assert compute_child_today_status(has_escalated=False, has_attention_share=False) == "NORMAL"
