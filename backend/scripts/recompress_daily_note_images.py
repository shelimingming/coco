#!/usr/bin/env python3
"""一次性：把已有每日小记 PNG 配图压缩为 JPEG 并覆盖写回 BOS。

用法（在 backend/ 下）：
  uv run python scripts/recompress_daily_note_images.py
  uv run python scripts/recompress_daily_note_images.py --dry-run
"""

from __future__ import annotations

import argparse
import asyncio
import logging

from sqlalchemy import text

from coco.config import get_settings
from coco.database import dispose_database, init_database
from coco.providers.bos_storage import build_bos_storage
from coco.providers.image_compress import compress_for_daily_note

logger = logging.getLogger("recompress_daily_note_images")


async def main(*, dry_run: bool) -> None:
    settings = get_settings()
    if not settings.bos_available:
        raise SystemExit("BOS 未配置，无法重压配图。")
    factory = init_database(settings)
    bos = build_bos_storage(settings)

    async with factory() as session:
        result = await session.execute(
            text(
                """
                SELECT id::text AS id, object_key, mime_type
                FROM coco.daily_note_images
                ORDER BY created_at ASC
                """
            )
        )
        rows = [dict(r) for r in result.mappings().all()]
    print(f"共 {len(rows)} 张配图")

    for row in rows:
        key = row["object_key"]
        raw = await bos.get_bytes(key)
        before = len(raw)
        compressed, mime = compress_for_daily_note(raw)
        after = len(compressed)
        print(
            f"{row['id'][:8]}… {row['mime_type']} {before} → {mime} {after} "
            f"({after / max(before, 1):.0%})"
        )
        if dry_run:
            continue
        # 已是 JPEG 且体积无收益，且 mime 已正确 → 跳过
        if mime == row["mime_type"] and after >= before * 0.95:
            print("  skip (no gain)")
            continue
        if after < before * 0.95 or mime != row["mime_type"]:
            await bos.put_bytes(key, compressed, content_type=mime)
        async with factory() as session:
            await session.execute(
                text(
                    """
                    UPDATE coco.daily_note_images
                    SET mime_type = :mime, updated_at = now()
                    WHERE id = CAST(:id AS uuid)
                    """
                ),
                {"mime": mime, "id": row["id"]},
            )
            await session.commit()
        print("  uploaded")

    await dispose_database()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    asyncio.run(main(dry_run=args.dry_run))
