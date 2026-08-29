"""万相文生图响应解析。"""

from __future__ import annotations

import pytest

from coco.providers.wan_image import parse_image_generate_response


def test_parse_sync_choices() -> None:
    data = {
        "output": {
            "choices": [
                {
                    "finish_reason": "stop",
                    "message": {
                        "role": "assistant",
                        "content": [
                            {
                                "image": "https://example.com/a.png",
                                "type": "image",
                            }
                        ],
                    },
                }
            ],
            "finished": True,
        },
        "usage": {"image_count": 1, "size": "2K"},
    }
    result = parse_image_generate_response(data, model="wan2.7-image")
    assert len(result.images) == 1
    assert result.images[0].url.endswith("a.png")
    assert result.size == "2K"
    assert result.model == "wan2.7-image"


def test_parse_async_results_fallback() -> None:
    data = {
        "output": {
            "task_status": "SUCCEEDED",
            "results": [{"url": "https://example.com/b.png"}],
        }
    }
    result = parse_image_generate_response(data, model="wan2.6-t2i")
    assert result.images[0].url.endswith("b.png")


def test_parse_empty_raises() -> None:
    with pytest.raises(RuntimeError, match="未返回图片"):
        parse_image_generate_response({"output": {"choices": []}}, model="wan2.7-image")
