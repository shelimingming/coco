"""family_invites 移除 6 位码与过期字段，仅保留链接 token

Revision ID: 20260826_0013
Revises: 20260826_0012
Create Date: 2026-08-26

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260826_0013"
down_revision: str | Sequence[str] | None = "20260826_0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_index("ix_coco_family_invites_code", table_name="family_invites", schema="coco")
    op.drop_column("family_invites", "code", schema="coco")
    op.drop_column("family_invites", "expires_at", schema="coco")


def downgrade() -> None:
    op.add_column(
        "family_invites",
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        schema="coco",
    )
    op.add_column(
        "family_invites",
        sa.Column("code", sa.String(length=8), nullable=False, server_default="000000"),
        schema="coco",
    )
    op.alter_column("family_invites", "code", server_default=None, schema="coco")
    op.create_index(
        "ix_coco_family_invites_code",
        "family_invites",
        ["code"],
        unique=False,
        schema="coco",
    )
