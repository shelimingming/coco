"""initial auth tables

Revision ID: 20260809_0001
Revises:
Create Date: 2026-08-09

"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260809_0001"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE SCHEMA IF NOT EXISTS coco")

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("phone_hash", sa.String(length=128), nullable=False),
        sa.Column("phone_masked", sa.String(length=32), nullable=False),
        sa.Column("display_name", sa.String(length=64), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
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
        sa.PrimaryKeyConstraint("id", name="pk_users"),
        sa.UniqueConstraint("phone_hash", name="uq_users_phone_hash"),
        schema="coco",
    )

    op.create_table(
        "phone_codes",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("phone_hash", sa.String(length=128), nullable=False),
        sa.Column("code_hash", sa.String(length=128), nullable=False),
        sa.Column("purpose", sa.String(length=16), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_phone_codes"),
        schema="coco",
    )
    op.create_index(
        "ix_coco_phone_codes_phone_hash",
        "phone_codes",
        ["phone_hash"],
        unique=False,
        schema="coco",
    )

    op.create_table(
        "auth_sessions",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("refresh_token_hash", sa.String(length=128), nullable=False),
        sa.Column("device_id", sa.String(length=200), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
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
            name="fk_auth_sessions_user_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_auth_sessions"),
        sa.UniqueConstraint("refresh_token_hash", name="uq_auth_sessions_refresh_token_hash"),
        schema="coco",
    )
    op.create_index(
        "ix_coco_auth_sessions_user_id",
        "auth_sessions",
        ["user_id"],
        unique=False,
        schema="coco",
    )


def downgrade() -> None:
    op.drop_index("ix_coco_auth_sessions_user_id", table_name="auth_sessions", schema="coco")
    op.drop_table("auth_sessions", schema="coco")
    op.drop_index("ix_coco_phone_codes_phone_hash", table_name="phone_codes", schema="coco")
    op.drop_table("phone_codes", schema="coco")
    op.drop_table("users", schema="coco")
