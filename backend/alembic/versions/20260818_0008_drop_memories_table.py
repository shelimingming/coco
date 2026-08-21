"""drop coco.memories；长期记忆改由 Mem0/pgvector 托管

Revision ID: 20260818_0008
Revises: 20260812_0007
Create Date: 2026-08-18

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "20260818_0008"
down_revision: str | Sequence[str] | None = "20260812_0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_index("ix_coco_memories_user_id", table_name="memories", schema="coco")
    op.drop_table("memories", schema="coco")


def downgrade() -> None:
    # 仅恢复表结构；Mem0 中的向量记忆不会回填
    op.create_table(
        "memories",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("category", sa.String(length=32), nullable=False),
        sa.Column("source", sa.String(length=16), nullable=False),
        sa.Column("confirmed", sa.Boolean(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["coco.users.id"],
            name="fk_memories_user_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_memories"),
        schema="coco",
    )
    op.create_index(
        "ix_coco_memories_user_id",
        "memories",
        ["user_id"],
        unique=False,
        schema="coco",
    )
