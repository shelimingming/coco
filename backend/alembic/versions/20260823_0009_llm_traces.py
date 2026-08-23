"""llm_traces：运营调试用的大模型调用记录

Revision ID: 20260823_0009
Revises: 20260818_0008
Create Date: 2026-08-23

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "20260823_0009"
down_revision: str | Sequence[str] | None = "20260818_0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "llm_traces",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("conversation_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("purpose", sa.String(length=32), nullable=False),
        sa.Column("modality", sa.String(length=16), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("model", sa.String(length=128), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("latency_ms", sa.Integer(), nullable=True),
        sa.Column("request_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("response_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("usage_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
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
            name="fk_llm_traces_user_id_users",
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["coco.conversations.id"],
            name="fk_llm_traces_conversation_id_conversations",
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_llm_traces"),
        schema="coco",
    )
    op.create_index(
        "ix_llm_traces_user_id_started_at",
        "llm_traces",
        ["user_id", "started_at"],
        unique=False,
        schema="coco",
    )
    op.create_index(
        "ix_llm_traces_purpose",
        "llm_traces",
        ["purpose"],
        unique=False,
        schema="coco",
    )
    op.create_index(
        "ix_llm_traces_status",
        "llm_traces",
        ["status"],
        unique=False,
        schema="coco",
    )
    op.create_index(
        "ix_llm_traces_conversation_id",
        "llm_traces",
        ["conversation_id"],
        unique=False,
        schema="coco",
    )


def downgrade() -> None:
    op.drop_index("ix_llm_traces_conversation_id", table_name="llm_traces", schema="coco")
    op.drop_index("ix_llm_traces_status", table_name="llm_traces", schema="coco")
    op.drop_index("ix_llm_traces_purpose", table_name="llm_traces", schema="coco")
    op.drop_index("ix_llm_traces_user_id_started_at", table_name="llm_traces", schema="coco")
    op.drop_table("llm_traces", schema="coco")
