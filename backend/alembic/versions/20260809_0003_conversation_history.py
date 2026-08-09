"""conversation history tables

Revision ID: 20260809_0003
Revises: 20260809_0002
Create Date: 2026-08-09

"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260809_0003"
down_revision: Union[str, Sequence[str], None] = "20260809_0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "conversations",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "started_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("channel", sa.String(length=32), nullable=False),
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
            name="fk_conversations_user_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_conversations"),
        schema="coco",
    )
    op.create_index(
        "ix_coco_conversations_user_id",
        "conversations",
        ["user_id"],
        unique=False,
        schema="coco",
    )
    # 列表按用户 + 开始时间查询；ORDER BY DESC 可走该索引反向扫描
    op.create_index(
        "ix_coco_conversations_user_id_started_at",
        "conversations",
        ["user_id", "started_at"],
        unique=False,
        schema="coco",
    )

    op.create_table(
        "conversation_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("conversation_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("seq", sa.Integer(), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("text", sa.Text(), nullable=True),
        sa.Column("tool_name", sa.String(length=64), nullable=True),
        sa.Column("arguments_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("result_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("display_summary", sa.Text(), nullable=True),
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
            ["conversation_id"],
            ["coco.conversations.id"],
            name="fk_conversation_items_conversation_id_conversations",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_conversation_items"),
        sa.UniqueConstraint(
            "conversation_id",
            "seq",
            name="uq_conversation_items_conversation_id_seq",
        ),
        schema="coco",
    )
    op.create_index(
        "ix_coco_conversation_items_conversation_id",
        "conversation_items",
        ["conversation_id"],
        unique=False,
        schema="coco",
    )
    op.create_index(
        "ix_coco_conversation_items_conversation_id_seq",
        "conversation_items",
        ["conversation_id", "seq"],
        unique=False,
        schema="coco",
    )


def downgrade() -> None:
    op.drop_index(
        "ix_coco_conversation_items_conversation_id_seq",
        table_name="conversation_items",
        schema="coco",
    )
    op.drop_index(
        "ix_coco_conversation_items_conversation_id",
        table_name="conversation_items",
        schema="coco",
    )
    op.drop_table("conversation_items", schema="coco")
    op.drop_index(
        "ix_coco_conversations_user_id_started_at",
        table_name="conversations",
        schema="coco",
    )
    op.drop_index("ix_coco_conversations_user_id", table_name="conversations", schema="coco")
    op.drop_table("conversations", schema="coco")
