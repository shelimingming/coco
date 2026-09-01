"""llm_traces：归一化 token 列，供运营用量聚合

Revision ID: 20260901_0018
Revises: 20260901_0017
Create Date: 2026-09-01

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260901_0018"
down_revision: str | Sequence[str] | None = "20260901_0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "llm_traces",
        sa.Column("input_tokens", sa.Integer(), nullable=True),
        schema="coco",
    )
    op.add_column(
        "llm_traces",
        sa.Column("output_tokens", sa.Integer(), nullable=True),
        schema="coco",
    )
    op.add_column(
        "llm_traces",
        sa.Column("total_tokens", sa.Integer(), nullable=True),
        schema="coco",
    )
    op.create_index(
        "ix_llm_traces_started_at_model",
        "llm_traces",
        ["started_at", "model"],
        unique=False,
        schema="coco",
    )
    # 历史文本/识图记录从 usage_json 回填；跳过被误标为 <redacted> 的脏数据
    op.execute(
        sa.text(
            """
            UPDATE coco.llm_traces
            SET
                input_tokens = CASE
                    WHEN usage_json->>'input_tokens' ~ '^[0-9]+$'
                        THEN (usage_json->>'input_tokens')::integer
                    WHEN usage_json->>'prompt_tokens' ~ '^[0-9]+$'
                        THEN (usage_json->>'prompt_tokens')::integer
                    ELSE NULL
                END,
                output_tokens = CASE
                    WHEN usage_json->>'output_tokens' ~ '^[0-9]+$'
                        THEN (usage_json->>'output_tokens')::integer
                    WHEN usage_json->>'completion_tokens' ~ '^[0-9]+$'
                        THEN (usage_json->>'completion_tokens')::integer
                    ELSE NULL
                END,
                total_tokens = CASE
                    WHEN usage_json->>'total_tokens' ~ '^[0-9]+$'
                        THEN (usage_json->>'total_tokens')::integer
                    ELSE NULL
                END
            WHERE usage_json IS NOT NULL
              AND (
                usage_json ? 'total_tokens'
                OR usage_json ? 'prompt_tokens'
                OR usage_json ? 'input_tokens'
              )
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE coco.llm_traces
            SET total_tokens = input_tokens + output_tokens
            WHERE total_tokens IS NULL
              AND input_tokens IS NOT NULL
              AND output_tokens IS NOT NULL
            """
        )
    )


def downgrade() -> None:
    op.drop_index("ix_llm_traces_started_at_model", table_name="llm_traces", schema="coco")
    op.drop_column("llm_traces", "total_tokens", schema="coco")
    op.drop_column("llm_traces", "output_tokens", schema="coco")
    op.drop_column("llm_traces", "input_tokens", schema="coco")
