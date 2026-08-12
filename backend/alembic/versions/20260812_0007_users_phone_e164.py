"""users 增加登录手机号明文，供绑定子女一键拨打

Revision ID: 20260812_0007
Revises: 20260812_0006
Create Date: 2026-08-12

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260812_0007"
down_revision: str | Sequence[str] | None = "20260812_0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 存量用户可空；下次登录会回填。验证码仍只存 hash。
    op.add_column(
        "users",
        sa.Column("phone_e164", sa.String(length=20), nullable=True),
        schema="coco",
    )


def downgrade() -> None:
    op.drop_column("users", "phone_e164", schema="coco")
