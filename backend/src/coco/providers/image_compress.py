"""配图压缩：万相 PNG 过大，上传 BOS 前转 JPEG 以加速前端加载。"""

from __future__ import annotations

import io
import logging

from PIL import Image

logger = logging.getLogger(__name__)

# 手机手账区约 390 宽；长边 1280 足够清晰
_DEFAULT_MAX_EDGE = 1280
_DEFAULT_JPEG_QUALITY = 82


def compress_for_daily_note(
    data: bytes,
    *,
    max_edge: int = _DEFAULT_MAX_EDGE,
    quality: int = _DEFAULT_JPEG_QUALITY,
) -> tuple[bytes, str]:
    """压缩配图为 JPEG；失败则原样返回（不阻断生图）。"""
    if not data:
        return data, "image/jpeg"
    try:
        with Image.open(io.BytesIO(data)) as im:
            # JPEG 不支持透明度；水彩底也用白底更稳
            rgb = im.convert("RGB")
            w, h = rgb.size
            long_edge = max(w, h)
            if long_edge > max_edge:
                scale = max_edge / long_edge
                rgb = rgb.resize(
                    (max(1, int(w * scale)), max(1, int(h * scale))),
                    Image.Resampling.LANCZOS,
                )
            out = io.BytesIO()
            rgb.save(out, format="JPEG", quality=quality, optimize=True)
            compressed = out.getvalue()
        if not compressed:
            return data, "image/png"
        logger.info(
            "daily_note_image_compressed before=%s after=%s ratio=%.2f",
            len(data),
            len(compressed),
            len(compressed) / max(len(data), 1),
        )
        return compressed, "image/jpeg"
    except Exception:
        logger.warning("daily_note_image_compress_failed", exc_info=True)
        return data, "image/png"
