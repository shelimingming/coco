"""用量聚合：北京时间日界与排名。"""

from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import uuid4

import pytest
from coco.models.llm_trace import LlmTrace, LlmTraceModality, LlmTraceStatus
from coco.models.user import User
from coco_admin.usage.service import _cst_date_bounds, collect_usage_stats
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker


def test_cst_date_bounds() -> None:
    start_utc, end_utc = _cst_date_bounds(date(2026, 9, 1), date(2026, 9, 1))
    assert start_utc == datetime(2026, 8, 31, 16, 0, tzinfo=UTC)
    assert end_utc == datetime(2026, 9, 1, 16, 0, tzinfo=UTC)


@pytest.mark.integration
@pytest.mark.asyncio
async def test_collect_usage_stats_ranking(
    session_factory: async_sessionmaker[AsyncSession],
) -> None:
    user_high = User(
        id=uuid4(),
        phone_hash=f"hash-high-{uuid4()}",
        phone_e164="+8613800000001",
        phone_masked="138****0001",
        display_name="高用量",
        role="parent",
        status="active",
    )
    user_low = User(
        id=uuid4(),
        phone_hash=f"hash-low-{uuid4()}",
        phone_e164="+8613800000002",
        phone_masked="138****0002",
        display_name="低用量",
        role="child",
        status="active",
    )
    # 北京时间 2026-09-01 中午，落在同一统计日
    started = datetime(2026, 9, 1, 4, 0, tzinfo=UTC)
    traces = [
        LlmTrace(
            id=uuid4(),
            user_id=user_high.id,
            purpose="text_title",
            modality=LlmTraceModality.TEXT.value,
            provider="dashscope",
            model="qwen-plus",
            status=LlmTraceStatus.OK.value,
            input_tokens=100,
            output_tokens=20,
            total_tokens=120,
            started_at=started,
        ),
        LlmTrace(
            id=uuid4(),
            user_id=user_high.id,
            purpose="voice_turn",
            modality=LlmTraceModality.REALTIME.value,
            provider="dashscope",
            model="qwen-audio-3.0-realtime-plus",
            status=LlmTraceStatus.OK.value,
            input_tokens=50,
            output_tokens=10,
            total_tokens=60,
            started_at=started,
        ),
        LlmTrace(
            id=uuid4(),
            user_id=user_low.id,
            purpose="text_title",
            modality=LlmTraceModality.TEXT.value,
            provider="dashscope",
            model="qwen-plus",
            status=LlmTraceStatus.OK.value,
            input_tokens=10,
            output_tokens=2,
            total_tokens=12,
            started_at=started,
        ),
        LlmTrace(
            id=uuid4(),
            user_id=user_low.id,
            purpose="text_title",
            modality=LlmTraceModality.TEXT.value,
            provider="dashscope",
            model="qwen-plus",
            status=LlmTraceStatus.ERROR.value,
            input_tokens=999,
            output_tokens=1,
            total_tokens=1000,
            started_at=started,
        ),
    ]

    async with session_factory() as session:
        session.add_all([user_high, user_low, *traces])
        await session.commit()

        stats = await collect_usage_stats(
            session,
            start_date=date(2026, 9, 1),
            end_date=date(2026, 9, 1),
        )
        filtered = await collect_usage_stats(
            session,
            start_date=date(2026, 9, 1),
            end_date=date(2026, 9, 1),
            model="qwen-plus",
        )

    assert stats["summary"]["total_tokens"] == 192
    assert stats["summary"]["active_users"] == 2
    assert len(stats["ranking"]) == 2
    assert stats["ranking"][0]["display_name"] == "高用量"
    assert stats["ranking"][0]["total_tokens"] == 180
    assert stats["ranking"][1]["total_tokens"] == 12
    assert filtered["summary"]["total_tokens"] == 132
    assert len(filtered["by_model"]) == 1
    assert filtered["by_model"][0]["model"] == "qwen-plus"
