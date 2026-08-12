"""reminder child suggestion: PENDING_CONFIRM + suggested_by

Revision ID: 20260812_0006
Revises: 20260810_0005
Create Date: 2026-08-12

"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "20260812_0006"
down_revision: Union[str, Sequence[str], None] = "20260810_0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "reminders",
        sa.Column("suggested_by_user_id", sa.Uuid(), nullable=True),
        schema="coco",
    )
    op.create_index(
        "ix_coco_reminders_suggested_by_user_id",
        "reminders",
        ["suggested_by_user_id"],
        unique=False,
        schema="coco",
    )
    op.create_foreign_key(
        "fk_reminders_suggested_by_user_id",
        "reminders",
        "users",
        ["suggested_by_user_id"],
        ["id"],
        source_schema="coco",
        referent_schema="coco",
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_reminders_suggested_by_user_id",
        "reminders",
        schema="coco",
        type_="foreignkey",
    )
    op.drop_index(
        "ix_coco_reminders_suggested_by_user_id",
        table_name="reminders",
        schema="coco",
    )
    op.drop_column("reminders", "suggested_by_user_id", schema="coco")
