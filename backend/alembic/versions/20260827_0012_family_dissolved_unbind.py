"""解绑软删除：dissolved 时允许 parent/child 均为空

Revision ID: 20260827_0012
Revises: 20260824_0011
Create Date: 2026-08-27

"""

from __future__ import annotations

from typing import Sequence, Union

from alembic import op

revision: str = "20260827_0012"
down_revision: Union[str, Sequence[str], None] = "20260824_0011"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 原约束要求至少一侧有用户；解绑需两侧皆空 + status=dissolved
    op.drop_constraint("ck_families_has_member", "families", schema="coco", type_="check")
    op.create_check_constraint(
        "ck_families_has_member",
        "families",
        "parent_user_id IS NOT NULL OR child_user_id IS NOT NULL OR status = 'dissolved'",
        schema="coco",
    )


def downgrade() -> None:
    op.drop_constraint("ck_families_has_member", "families", schema="coco", type_="check")
    op.create_check_constraint(
        "ck_families_has_member",
        "families",
        "parent_user_id IS NOT NULL OR child_user_id IS NOT NULL",
        schema="coco",
    )
