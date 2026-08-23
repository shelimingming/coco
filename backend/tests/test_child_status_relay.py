"""报平安转述：第三人称校验与违规回退。"""

from __future__ import annotations

from coco.providers.qwen_text import (
    fallback_third_person_relay,
    looks_like_child_first_person,
    sanitize_child_status_relay,
)


def test_looks_like_child_first_person_parent_address() -> None:
    assert looks_like_child_first_person("妈，我刚吃完饭啦！")
    assert looks_like_child_first_person("妈妈，一切都好")
    assert looks_like_child_first_person("爸，我已经到家了")
    assert looks_like_child_first_person("爸爸，准备休息了")


def test_looks_like_child_first_person_wo_opening() -> None:
    assert looks_like_child_first_person("我刚吃完饭")
    assert looks_like_child_first_person("我已经到家")
    assert looks_like_child_first_person("我在忙，一切都好")
    assert looks_like_child_first_person("我准备休息")


def test_looks_like_child_first_person_allows_third_person() -> None:
    assert not looks_like_child_first_person("小林已经吃过饭了，让您放心")
    assert not looks_like_child_first_person("小林说，吃过饭了")
    assert not looks_like_child_first_person("孩子传来消息，已经到家")


def test_fallback_third_person_relay() -> None:
    assert fallback_third_person_relay("吃过饭了", child_name="小林") == "小林说，吃过饭了"
    assert fallback_third_person_relay("", child_name="小林") == "小林传来消息，让您放心。"
    assert fallback_third_person_relay("已经到家", child_name="") == "孩子说，已经到家"


def test_sanitize_child_status_relay_rejects_first_person() -> None:
    result = sanitize_child_status_relay(
        "妈，我刚吃完饭啦！",
        original="吃过饭了",
        child_name="小林",
    )
    assert result == "小林说，吃过饭了"
    assert "妈" not in result
    assert not result.startswith("我")


def test_sanitize_child_status_relay_keeps_third_person() -> None:
    ok = "小林已经吃过饭了，让您放心"
    assert sanitize_child_status_relay(ok, original="吃过饭了", child_name="小林") == ok
