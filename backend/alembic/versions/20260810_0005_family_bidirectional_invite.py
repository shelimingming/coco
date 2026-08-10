"""family bidirectional invite: parent_user_id nullable

Revision ID: 20260810_0005
Revises: 20260809_0004
Create Date: 2026-08-10

"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "20260810_0005"
down_revision: Union[str, Sequence[str], None] = "20260809_0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 子女也可先建 pending 家庭，故父母侧允许为空
    op.alter_column(
        "families",
        "parent_user_id",
        existing_type=sa.Uuid(),
        nullable=True,
        schema="coco",
    )
    op.create_check_constraint(
        "ck_families_has_member",
        "families",
        "parent_user_id IS NOT NULL OR child_user_id IS NOT NULL",
        schema="coco",
    )


def downgrade() -> None:
    op.drop_constraint("ck_families_has_member", "families", schema="coco", type_="check")
    # 回滚前若存在仅子女侧 pending，需先清理，否则 NOT NULL 会失败
    op.execute(
        """
        DELETE FROM coco.family_invites
        WHERE family_id IN (
            SELECT id FROM coco.families WHERE parent_user_id IS NULL
        )
        """
    )
    op.execute("DELETE FROM coco.families WHERE parent_user_id IS NULL")
    op.alter_column(
        "families",
        "parent_user_id",
        existing_type=sa.Uuid(),
        nullable=False,
        schema="coco",
    )
