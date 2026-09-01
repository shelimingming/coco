"""每日小记：默认关闭自动生成

Revision ID: 20260901_0017
Revises: 20260830_0016
Create Date: 2026-09-01

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260901_0017"
down_revision: str | Sequence[str] | None = "20260830_0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.alter_column(
        "daily_note_settings",
        "generate_enabled",
        server_default=sa.false(),
        schema="coco",
    )


def downgrade() -> None:
    op.alter_column(
        "daily_note_settings",
        "generate_enabled",
        server_default=sa.true(),
        schema="coco",
    )
