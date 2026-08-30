"""每日小记配图压缩单测。"""

from __future__ import annotations

import io

from PIL import Image

from coco.providers.image_compress import compress_for_daily_note


def _png_bytes(width: int = 800, height: int = 1200) -> bytes:
    im = Image.new("RGB", (width, height), color=(240, 200, 160))
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


def test_compress_png_to_jpeg() -> None:
    raw = _png_bytes()
    out, mime = compress_for_daily_note(raw)
    assert mime == "image/jpeg"
    assert out.startswith(b"\xff\xd8\xff")
    with Image.open(io.BytesIO(out)) as im:
        assert im.format == "JPEG"
        assert max(im.size) <= 1280


def test_compress_downscales_huge_edge() -> None:
    raw = _png_bytes(2000, 3000)
    out, mime = compress_for_daily_note(raw, max_edge=1280)
    assert mime == "image/jpeg"
    with Image.open(io.BytesIO(out)) as im:
        assert max(im.size) <= 1280
