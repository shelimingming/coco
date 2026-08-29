"""每日小记表 + users.gender

Revision ID: 20260829_0013
Revises: 20260827_0012
Create Date: 2026-08-29

"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260829_0013"
down_revision: Union[str, Sequence[str], None] = "20260827_0012"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "gender",
            sa.String(length=16),
            nullable=False,
            server_default="unknown",
        ),
        schema="coco",
    )

    op.create_table(
        "daily_note_settings",
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("generate_enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column(
            "share_to_child_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column("generate_hour", sa.Integer(), nullable=False, server_default="20"),
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
            name="fk_daily_note_settings_user_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("user_id", name="pk_daily_note_settings"),
        schema="coco",
    )

    op.create_table(
        "daily_notes",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("parent_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("note_date", sa.Date(), nullable=False),
        sa.Column(
            "items_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("body_text", sa.Text(), nullable=False, server_default=""),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
        sa.Column("source", sa.String(length=16), nullable=False, server_default="manual"),
        sa.Column("shared_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("share_error", sa.Text(), nullable=True),
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
            ["parent_id"],
            ["coco.users.id"],
            name="fk_daily_notes_parent_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_daily_notes"),
        sa.UniqueConstraint(
            "parent_id",
            "note_date",
            name="uq_daily_notes_parent_id_note_date",
        ),
        schema="coco",
    )
    op.create_index(
        "ix_coco_daily_notes_parent_id",
        "daily_notes",
        ["parent_id"],
        unique=False,
        schema="coco",
    )

    op.create_table(
        "daily_note_images",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("daily_note_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("seq", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "mime_type",
            sa.String(length=64),
            nullable=False,
            server_default="image/png",
        ),
        sa.Column("data", sa.LargeBinary(), nullable=False),
        sa.Column("prompt", sa.Text(), nullable=True),
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
            ["daily_note_id"],
            ["coco.daily_notes.id"],
            name="fk_daily_note_images_daily_note_id_daily_notes",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_daily_note_images"),
        schema="coco",
    )
    op.create_index(
        "ix_coco_daily_note_images_daily_note_id",
        "daily_note_images",
        ["daily_note_id"],
        unique=False,
        schema="coco",
    )


def downgrade() -> None:
    op.drop_index(
        "ix_coco_daily_note_images_daily_note_id",
        table_name="daily_note_images",
        schema="coco",
    )
    op.drop_table("daily_note_images", schema="coco")
    op.drop_index("ix_coco_daily_notes_parent_id", table_name="daily_notes", schema="coco")
    op.drop_table("daily_notes", schema="coco")
    op.drop_table("daily_note_settings", schema="coco")
    op.drop_column("users", "gender", schema="coco")
