"""每日小记：第一人称日记字段 title/header/closing/extraction

Revision ID: 20260830_0016
Revises: 20260830_0015
Create Date: 2026-08-30

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "20260830_0016"
down_revision: str | Sequence[str] | None = "20260830_0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "daily_notes",
        sa.Column("title", sa.String(length=64), nullable=False, server_default=""),
        schema="coco",
    )
    op.add_column(
        "daily_notes",
        sa.Column("header_line", sa.String(length=128), nullable=False, server_default=""),
        schema="coco",
    )
    op.add_column(
        "daily_notes",
        sa.Column("closing", sa.Text(), nullable=False, server_default=""),
        schema="coco",
    )
    op.add_column(
        "daily_notes",
        sa.Column(
            "extraction_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        schema="coco",
    )
    # 去掉 server_default，后续写入由应用负责
    op.alter_column("daily_notes", "title", server_default=None, schema="coco")
    op.alter_column("daily_notes", "header_line", server_default=None, schema="coco")
    op.alter_column("daily_notes", "closing", server_default=None, schema="coco")
    op.alter_column("daily_notes", "extraction_json", server_default=None, schema="coco")


def downgrade() -> None:
    op.drop_column("daily_notes", "extraction_json", schema="coco")
    op.drop_column("daily_notes", "closing", schema="coco")
    op.drop_column("daily_notes", "header_line", schema="coco")
    op.drop_column("daily_notes", "title", schema="coco")
