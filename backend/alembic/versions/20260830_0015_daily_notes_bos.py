"""每日小记配图迁百度 BOS：BYTEA → object_key

Revision ID: 20260830_0015
Revises: 20260829_0014
Create Date: 2026-08-30

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "20260830_0015"
down_revision: str | Sequence[str] | None = "20260829_0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _migrate_blobs_to_bos() -> None:
    """把存量 BYTEA 上传到 BOS 并回填 object_key；有图但无 BOS 配置则失败。"""
    from io import BytesIO

    from coco.config import get_settings
    from coco.providers.bos_storage import build_bos_storage

    get_settings.cache_clear()
    settings = get_settings()
    bind = op.get_bind()

    images = (
        bind.execute(
            sa.text(
                "SELECT i.id, i.data, i.mime_type, n.parent_id, i.daily_note_id "
                "FROM coco.daily_note_images i "
                "JOIN coco.daily_notes n ON n.id = i.daily_note_id "
                "WHERE i.data IS NOT NULL"
            )
        )
        .mappings()
        .all()
    )
    settings_rows = (
        bind.execute(
            sa.text(
                "SELECT user_id, parent_photo_data, parent_photo_mime "
                "FROM coco.daily_note_settings "
                "WHERE parent_photo_data IS NOT NULL"
            )
        )
        .mappings()
        .all()
    )

    if not images and not settings_rows:
        return

    if not settings.bos_available:
        raise RuntimeError("存在每日小记图片 BYTEA，但未配置 COCO_BOS_*，无法迁到 BOS")

    bos = build_bos_storage(settings)

    for row in images:
        image_id = row["id"]
        parent_id = row["parent_id"]
        note_id = row["daily_note_id"]
        mime = (row["mime_type"] or "image/png").split(";")[0].strip()
        data = bytes(row["data"])
        key = f"daily-notes/{parent_id}/{note_id}/{image_id}"
        bos._client.put_object(
            bos.bucket,
            key,
            BytesIO(data),
            len(data),
            content_type=mime,
        )
        bind.execute(
            sa.text("UPDATE coco.daily_note_images SET object_key = :key WHERE id = :id"),
            {"key": key, "id": image_id},
        )

    for row in settings_rows:
        user_id = row["user_id"]
        mime = (row["parent_photo_mime"] or "image/jpeg").split(";")[0].strip()
        data = bytes(row["parent_photo_data"])
        key = f"daily-notes/{user_id}/parent-photo"
        bos._client.put_object(
            bos.bucket,
            key,
            BytesIO(data),
            len(data),
            content_type=mime,
        )
        bind.execute(
            sa.text(
                "UPDATE coco.daily_note_settings "
                "SET parent_photo_object_key = :key WHERE user_id = :uid"
            ),
            {"key": key, "uid": user_id},
        )


def upgrade() -> None:
    op.add_column(
        "daily_note_images",
        sa.Column("object_key", sa.String(length=512), nullable=True),
        schema="coco",
    )
    op.add_column(
        "daily_note_settings",
        sa.Column("parent_photo_object_key", sa.String(length=512), nullable=True),
        schema="coco",
    )

    _migrate_blobs_to_bos()

    # 无存量时可能仍为空：用占位键避免 NOT NULL 失败（正常环境不应有空 data 行）
    op.execute(
        sa.text(
            "UPDATE coco.daily_note_images "
            "SET object_key = 'migrated-missing/' || id::text "
            "WHERE object_key IS NULL"
        )
    )
    op.alter_column(
        "daily_note_images",
        "object_key",
        existing_type=sa.String(length=512),
        nullable=False,
        schema="coco",
    )

    op.drop_column("daily_note_images", "data", schema="coco")
    op.drop_column("daily_note_settings", "parent_photo_data", schema="coco")


def downgrade() -> None:
    op.add_column(
        "daily_note_images",
        sa.Column("data", postgresql.BYTEA(), nullable=True),
        schema="coco",
    )
    op.add_column(
        "daily_note_settings",
        sa.Column("parent_photo_data", postgresql.BYTEA(), nullable=True),
        schema="coco",
    )
    # 降级不回拉 BOS 二进制；空 BYTEA 仅占位
    op.execute(sa.text("UPDATE coco.daily_note_images SET data = ''::bytea WHERE data IS NULL"))
    op.alter_column(
        "daily_note_images",
        "data",
        existing_type=postgresql.BYTEA(),
        nullable=False,
        schema="coco",
    )
    op.drop_column("daily_note_images", "object_key", schema="coco")
    op.drop_column("daily_note_settings", "parent_photo_object_key", schema="coco")
