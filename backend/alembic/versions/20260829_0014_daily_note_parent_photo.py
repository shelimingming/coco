"""每日小记：老人可选参考照字段

Revision ID: 20260829_0014
Revises: 20260829_0013
Create Date: 2026-08-29

"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "20260829_0014"
down_revision: Union[str, Sequence[str], None] = "20260829_0013"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "daily_note_settings",
        sa.Column("parent_photo_data", sa.LargeBinary(), nullable=True),
        schema="coco",
    )
    op.add_column(
        "daily_note_settings",
        sa.Column("parent_photo_mime", sa.String(length=64), nullable=True),
        schema="coco",
    )


def downgrade() -> None:
    op.drop_column("daily_note_settings", "parent_photo_mime", schema="coco")
    op.drop_column("daily_note_settings", "parent_photo_data", schema="coco")
