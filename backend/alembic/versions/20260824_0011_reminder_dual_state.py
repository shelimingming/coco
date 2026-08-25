"""提醒 occurrence 拆成投递进展与用户反馈两个正交字段

Revision ID: 20260824_0011
Revises: 20260824_0010
Create Date: 2026-08-24

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260824_0011"
down_revision: str | Sequence[str] | None = "20260824_0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "reminders",
        sa.Column(
            "timing_mode",
            sa.String(length=16),
            nullable=False,
            server_default="EXACT",
        ),
        schema="coco",
    )
    op.add_column(
        "reminders",
        sa.Column(
            "allowed_delay_minutes",
            sa.Integer(),
            nullable=False,
            server_default="15",
        ),
        schema="coco",
    )
    op.add_column(
        "reminders",
        sa.Column(
            "escalation_policy",
            sa.String(length=32),
            nullable=False,
            server_default="NONE",
        ),
        schema="coco",
    )
    op.add_column(
        "reminders",
        sa.Column("revision", sa.Integer(), nullable=False, server_default="1"),
        schema="coco",
    )

    op.add_column(
        "reminder_occurrences",
        sa.Column(
            "delivery_state",
            sa.String(length=32),
            nullable=False,
            server_default="CLOSED",
        ),
        schema="coco",
    )
    op.add_column(
        "reminder_occurrences",
        sa.Column(
            "response_status",
            sa.String(length=32),
            nullable=False,
            server_default="NONE",
        ),
        schema="coco",
    )
    op.add_column(
        "reminder_occurrences",
        sa.Column(
            "reminder_revision",
            sa.Integer(),
            nullable=False,
            server_default="1",
        ),
        schema="coco",
    )
    op.add_column(
        "reminder_occurrences",
        sa.Column(
            "title_snapshot",
            sa.String(length=200),
            nullable=False,
            server_default="",
        ),
        schema="coco",
    )
    op.add_column(
        "reminder_occurrences",
        sa.Column("snooze_until", sa.DateTime(timezone=True), nullable=True),
        schema="coco",
    )
    op.add_column(
        "reminder_occurrences",
        sa.Column("attempt_count", sa.Integer(), nullable=False, server_default="0"),
        schema="coco",
    )
    op.add_column(
        "reminder_occurrences",
        sa.Column(
            "response_source",
            sa.String(length=16),
            nullable=False,
            server_default="NONE",
        ),
        schema="coco",
    )

    op.drop_index(
        "ix_coco_reminder_occurrences_state",
        table_name="reminder_occurrences",
        schema="coco",
    )
    op.drop_column("reminder_occurrences", "state", schema="coco")
    op.create_index(
        "ix_coco_reminder_occurrences_delivery_state",
        "reminder_occurrences",
        ["delivery_state"],
        unique=False,
        schema="coco",
    )

    op.alter_column("reminders", "timing_mode", server_default=None, schema="coco")
    op.alter_column("reminders", "allowed_delay_minutes", server_default=None, schema="coco")
    op.alter_column("reminders", "escalation_policy", server_default=None, schema="coco")
    op.alter_column("reminders", "revision", server_default=None, schema="coco")
    op.alter_column(
        "reminder_occurrences",
        "delivery_state",
        server_default=None,
        schema="coco",
    )
    op.alter_column(
        "reminder_occurrences",
        "response_status",
        server_default=None,
        schema="coco",
    )
    op.alter_column(
        "reminder_occurrences",
        "reminder_revision",
        server_default=None,
        schema="coco",
    )
    op.alter_column(
        "reminder_occurrences",
        "title_snapshot",
        server_default=None,
        schema="coco",
    )
    op.alter_column(
        "reminder_occurrences",
        "attempt_count",
        server_default=None,
        schema="coco",
    )
    op.alter_column(
        "reminder_occurrences",
        "response_source",
        server_default=None,
        schema="coco",
    )


def downgrade() -> None:
    op.add_column(
        "reminder_occurrences",
        sa.Column(
            "state",
            sa.String(length=32),
            nullable=False,
            server_default="DONE",
        ),
        schema="coco",
    )
    op.drop_index(
        "ix_coco_reminder_occurrences_delivery_state",
        table_name="reminder_occurrences",
        schema="coco",
    )
    op.create_index(
        "ix_coco_reminder_occurrences_state",
        "reminder_occurrences",
        ["state"],
        unique=False,
        schema="coco",
    )
    op.drop_column("reminder_occurrences", "response_source", schema="coco")
    op.drop_column("reminder_occurrences", "attempt_count", schema="coco")
    op.drop_column("reminder_occurrences", "snooze_until", schema="coco")
    op.drop_column("reminder_occurrences", "title_snapshot", schema="coco")
    op.drop_column("reminder_occurrences", "reminder_revision", schema="coco")
    op.drop_column("reminder_occurrences", "response_status", schema="coco")
    op.drop_column("reminder_occurrences", "delivery_state", schema="coco")
    op.drop_column("reminders", "revision", schema="coco")
    op.drop_column("reminders", "escalation_policy", schema="coco")
    op.drop_column("reminders", "allowed_delay_minutes", schema="coco")
    op.drop_column("reminders", "timing_mode", schema="coco")
    op.alter_column(
        "reminder_occurrences",
        "state",
        server_default=None,
        schema="coco",
    )
