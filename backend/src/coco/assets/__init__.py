"""后端静态资源路径（可可参考图等）。"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

_ASSETS_DIR = Path(__file__).resolve().parent


@lru_cache(maxsize=1)
def load_coco_reference_png() -> bytes:
    """每日小记配图固定参考：金毛可可形象。"""
    path = _ASSETS_DIR / "coco_reference.png"
    if not path.is_file():
        raise FileNotFoundError(f"缺少可可参考图：{path}")
    return path.read_bytes()
