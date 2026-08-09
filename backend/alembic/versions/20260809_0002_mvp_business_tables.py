"""mvp business tables

Revision ID: 20260809_0002
Revises: 20260809_0001
Create Date: 2026-08-09

"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260809_0002"
down_revision: Union[str, Sequence[str], None] = "20260809_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "families",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("parent_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_user_id", postgresql.UUID(as_uuid=True), nullable=True),
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
        sa.ForeignKeyConstraint(
            ["parent_user_id"],
            ["coco.users.id"],
            name="fk_families_parent_user_id_users",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["child_user_id"],
            ["coco.users.id"],
            name="fk_families_child_user_id_users",
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_families"),
        sa.UniqueConstraint("parent_user_id", name="uq_families_parent_user_id"),
        sa.UniqueConstraint("child_user_id", name="uq_families_child_user_id"),
        schema="coco",
    )

    op.create_table(
        "family_invites",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("code", sa.String(length=8), nullable=False),
        sa.Column("inviter_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("family_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["inviter_user_id"],
            ["coco.users.id"],
            name="fk_family_invites_inviter_user_id_users",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["family_id"],
            ["coco.families.id"],
            name="fk_family_invites_family_id_families",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_family_invites"),
        schema="coco",
    )
    op.create_index(
        "ix_coco_family_invites_code",
        "family_invites",
        ["code"],
        unique=False,
        schema="coco",
    )

    op.create_table(
        "reminders",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("schedule_type", sa.String(length=16), nullable=False),
        sa.Column("schedule_time", sa.Time(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("created_source", sa.String(length=16), nullable=False),
        sa.Column("next_trigger_at", sa.DateTime(timezone=True), nullable=True),
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
            name="fk_reminders_user_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_reminders"),
        schema="coco",
    )
    op.create_index(
        "ix_coco_reminders_user_id",
        "reminders",
        ["user_id"],
        unique=False,
        schema="coco",
    )
    op.create_index(
        "ix_coco_reminders_next_trigger_at",
        "reminders",
        ["next_trigger_at"],
        unique=False,
        schema="coco",
    )

    op.create_table(
        "reminder_occurrences",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("reminder_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("state", sa.String(length=32), nullable=False),
        sa.Column("first_notified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("second_notified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("escalated_at", sa.DateTime(timezone=True), nullable=True),
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
            ["reminder_id"],
            ["coco.reminders.id"],
            name="fk_reminder_occurrences_reminder_id_reminders",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_reminder_occurrences"),
        schema="coco",
    )
    op.create_index(
        "ix_coco_reminder_occurrences_reminder_id",
        "reminder_occurrences",
        ["reminder_id"],
        unique=False,
        schema="coco",
    )
    op.create_index(
        "ix_coco_reminder_occurrences_state",
        "reminder_occurrences",
        ["state"],
        unique=False,
        schema="coco",
    )

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

    op.create_table(
        "care_shares",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("parent_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
        sa.Column("urgency", sa.String(length=16), nullable=False),
        sa.Column("reply_expectation", sa.String(length=32), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("parent_confirmed", sa.Boolean(), nullable=False),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
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
            name="fk_care_shares_parent_id_users",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["child_id"],
            ["coco.users.id"],
            name="fk_care_shares_child_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_care_shares"),
        schema="coco",
    )
    op.create_index(
        "ix_coco_care_shares_parent_id",
        "care_shares",
        ["parent_id"],
        unique=False,
        schema="coco",
    )
    op.create_index(
        "ix_coco_care_shares_child_id",
        "care_shares",
        ["child_id"],
        unique=False,
        schema="coco",
    )

    op.create_table(
        "family_messages",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("family_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("from_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("to_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("original_text", sa.Text(), nullable=False),
        sa.Column("delivered_text", sa.Text(), nullable=False),
        sa.Column("acknowledged_at", sa.DateTime(timezone=True), nullable=True),
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
            ["family_id"],
            ["coco.families.id"],
            name="fk_family_messages_family_id_families",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["from_user_id"],
            ["coco.users.id"],
            name="fk_family_messages_from_user_id_users",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["to_user_id"],
            ["coco.users.id"],
            name="fk_family_messages_to_user_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_family_messages"),
        schema="coco",
    )
    op.create_index(
        "ix_coco_family_messages_family_id",
        "family_messages",
        ["family_id"],
        unique=False,
        schema="coco",
    )

    op.create_table(
        "notifications",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("type", sa.String(length=32), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
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
            name="fk_notifications_user_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_notifications"),
        schema="coco",
    )
    op.create_index(
        "ix_coco_notifications_user_id",
        "notifications",
        ["user_id"],
        unique=False,
        schema="coco",
    )


def downgrade() -> None:
    op.drop_index("ix_coco_notifications_user_id", table_name="notifications", schema="coco")
    op.drop_table("notifications", schema="coco")
    op.drop_index("ix_coco_family_messages_family_id", table_name="family_messages", schema="coco")
    op.drop_table("family_messages", schema="coco")
    op.drop_index("ix_coco_care_shares_child_id", table_name="care_shares", schema="coco")
    op.drop_index("ix_coco_care_shares_parent_id", table_name="care_shares", schema="coco")
    op.drop_table("care_shares", schema="coco")
    op.drop_index("ix_coco_memories_user_id", table_name="memories", schema="coco")
    op.drop_table("memories", schema="coco")
    op.drop_index(
        "ix_coco_reminder_occurrences_state",
        table_name="reminder_occurrences",
        schema="coco",
    )
    op.drop_index(
        "ix_coco_reminder_occurrences_reminder_id",
        table_name="reminder_occurrences",
        schema="coco",
    )
    op.drop_table("reminder_occurrences", schema="coco")
    op.drop_index("ix_coco_reminders_next_trigger_at", table_name="reminders", schema="coco")
    op.drop_index("ix_coco_reminders_user_id", table_name="reminders", schema="coco")
    op.drop_table("reminders", schema="coco")
    op.drop_index("ix_coco_family_invites_code", table_name="family_invites", schema="coco")
    op.drop_table("family_invites", schema="coco")
    op.drop_table("families", schema="coco")
