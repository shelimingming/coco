"""识图结果解析、看不清兜底与图片缓存。"""

from __future__ import annotations

from uuid import uuid4

from coco.modules.vision.image_cache import LookImageCache
from coco.providers.qwen_vision import parse_look_content, unclear_look_result


def test_parse_look_content_high() -> None:
    result = parse_look_content(
        '{"confidence":"high","headline":"保质期到 2026年8月18日",'
        '"detail":"今天还没有过期。","safety_note":"包装鼓起不要食用。",'
        '"scene_description":"一张食品包装特写，标签写着保质期到2026年8月18日。"}'
    )
    assert result.confidence == "high"
    assert "2026" in result.headline
    assert "过期" in result.detail
    assert "鼓起" in result.safety_note
    assert "食品包装" in result.scene_description


def test_parse_look_content_low_clears_headline() -> None:
    result = parse_look_content(
        '{"confidence":"low","headline":"可能是日期","detail":"","safety_note":"",'
        '"scene_description":"画面模糊，看不清文字。"}'
    )
    assert result.confidence == "low"
    assert result.headline == ""
    assert "看不太清" in result.detail
    assert "模糊" in result.scene_description


def test_parse_look_content_fenced_json() -> None:
    result = parse_look_content(
        '```json\n{"confidence":"high","headline":"快递柜通知",'
        '"detail":"今晚前取件。","safety_note":"",'
        '"scene_description":"手机截图，快递柜取件通知。"}\n```'
    )
    assert result.confidence == "high"
    assert result.headline == "快递柜通知"


def test_parse_look_content_falls_back_scene_from_headline() -> None:
    # 旧模型偶发漏写 scene_description
    result = parse_look_content(
        '{"confidence":"high","headline":"红烧肉","detail":"一盘家常菜。","safety_note":""}'
    )
    assert "红烧肉" in result.scene_description
    assert "家常菜" in result.scene_description


def test_unclear_look_result() -> None:
    result = unclear_look_result()
    assert result.confidence == "low"
    assert result.headline == ""
    assert "看不太清" in result.detail
    assert result.scene_description == result.detail


def test_look_image_cache_ttl() -> None:
    cache = LookImageCache(ttl_seconds=60)
    cid = uuid4()
    cache.put(cid, image_bytes=b"abc", mime="image/jpeg")
    hit = cache.get(cid)
    assert hit is not None
    assert hit.image_bytes == b"abc"
    cache.discard(cid)
    assert cache.get(cid) is None
