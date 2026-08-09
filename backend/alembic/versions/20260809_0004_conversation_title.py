"""conversation title for history list

Revision ID: 20260809_0004
Revises: 20260809_0003
Create Date: 2026-08-09

"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "20260809_0004"
down_revision: Union[str, Sequence[str], None] = "20260809_0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 结束通话后由 LLM 写入短标题，供历史列表展示
    op.add_column(
        "conversations",
        sa.Column("title", sa.String(length=64), nullable=True),
        schema="coco",
    )


def downgrade() -> None:
    op.drop_column("conversations", "title", schema="coco")
