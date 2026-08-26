"""family_invites 增加链接 token，支持邀请链接绑定

Revision ID: 20260826_0012
Revises: 20260824_0011
Create Date: 2026-08-26

"""

from __future__ import annotations

import secrets
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260826_0012"
down_revision: str | Sequence[str] | None = "20260824_0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "family_invites",
        sa.Column("token", sa.String(length=64), nullable=True),
        schema="coco",
    )
    # 存量邀请补 token，避免 unique 约束建不起来
    conn = op.get_bind()
    rows = conn.execute(
        sa.text("SELECT id FROM coco.family_invites WHERE token IS NULL")
    ).fetchall()
    for (invite_id,) in rows:
        token = secrets.token_urlsafe(22)
        conn.execute(
            sa.text("UPDATE coco.family_invites SET token = :token WHERE id = :id"),
            {"token": token, "id": invite_id},
        )
    op.alter_column(
        "family_invites",
        "token",
        nullable=False,
        schema="coco",
    )
    op.create_index(
        "ix_family_invites_token",
        "family_invites",
        ["token"],
        unique=True,
        schema="coco",
    )


def downgrade() -> None:
    op.drop_index("ix_family_invites_token", table_name="family_invites", schema="coco")
    op.drop_column("family_invites", "token", schema="coco")
