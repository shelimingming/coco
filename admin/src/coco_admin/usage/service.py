"""运营用量聚合：按北京时间日界统计 token。"""

from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from coco.models.llm_trace import LlmTrace, LlmTraceStatus
from coco.models.user import User
from sqlalchemy import cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.types import Date

CST = ZoneInfo("Asia/Shanghai")
USAGE_TIMEZONE_LABEL = "Asia/Shanghai"


def _cst_date_bounds(start_date: date, end_date: date) -> tuple[datetime, datetime]:
    """北京时间闭区间 [start_date, end_date] 转为 UTC 查询半开区间。"""
    if end_date < start_date:
        end_date = start_date
    start_cst = datetime.combine(start_date, time.min, tzinfo=CST)
    end_cst = datetime.combine(end_date + timedelta(days=1), time.min, tzinfo=CST)
    return start_cst.astimezone(UTC), end_cst.astimezone(UTC)


def _shanghai_day_expr() -> Any:
    return cast(func.timezone(USAGE_TIMEZONE_LABEL, LlmTrace.started_at), Date)


def _usage_filters(
    *,
    start_utc: datetime,
    end_utc: datetime,
    model: str | None,
) -> list[Any]:
    clauses: list[Any] = [
        LlmTrace.started_at >= start_utc,
        LlmTrace.started_at < end_utc,
        LlmTrace.status == LlmTraceStatus.OK.value,
        LlmTrace.total_tokens.is_not(None),
        LlmTrace.user_id.is_not(None),
    ]
    if model:
        clauses.append(LlmTrace.model == model)
    return clauses


async def list_usage_models(session: AsyncSession) -> list[str]:
    rows = (
        await session.execute(
            select(LlmTrace.model)
            .where(LlmTrace.total_tokens.is_not(None))
            .distinct()
            .order_by(LlmTrace.model)
        )
    ).all()
    return [str(row[0]) for row in rows if row[0]]


async def collect_usage_stats(
    session: AsyncSession,
    *,
    start_date: date,
    end_date: date,
    model: str | None = None,
    limit: int = 50,
    now: datetime | None = None,
) -> dict[str, Any]:
    now = now or datetime.now(UTC)
    start_utc, end_utc = _cst_date_bounds(start_date, end_date)
    filters = _usage_filters(start_utc=start_utc, end_utc=end_utc, model=model)
    shanghai_day = _shanghai_day_expr()

    summary_row = (
        await session.execute(
            select(
                func.coalesce(func.sum(LlmTrace.input_tokens), 0),
                func.coalesce(func.sum(LlmTrace.output_tokens), 0),
                func.coalesce(func.sum(LlmTrace.total_tokens), 0),
                func.count(),
                func.count(func.distinct(LlmTrace.user_id)),
            ).where(*filters)
        )
    ).one()

    by_model_rows = (
        await session.execute(
            select(
                LlmTrace.model,
                func.coalesce(func.sum(LlmTrace.total_tokens), 0),
                func.count(),
            )
            .where(*filters)
            .group_by(LlmTrace.model)
            .order_by(func.sum(LlmTrace.total_tokens).desc())
        )
    ).all()

    top_model = str(by_model_rows[0][0]) if by_model_rows else None

    ranking_rows = (
        await session.execute(
            select(
                LlmTrace.user_id,
                func.coalesce(func.sum(LlmTrace.input_tokens), 0),
                func.coalesce(func.sum(LlmTrace.output_tokens), 0),
                func.coalesce(func.sum(LlmTrace.total_tokens), 0),
                func.count(),
            )
            .where(*filters)
            .group_by(LlmTrace.user_id)
            .order_by(func.sum(LlmTrace.total_tokens).desc())
            .limit(limit)
        )
    ).all()

    user_ids = [row[0] for row in ranking_rows]
    users_by_id: dict[Any, User] = {}
    if user_ids:
        users_by_id = {
            user.id: user
            for user in (await session.scalars(select(User).where(User.id.in_(user_ids)))).all()
        }

    ranking: list[dict[str, Any]] = []
    for index, row in enumerate(ranking_rows, start=1):
        user = users_by_id.get(row[0])
        ranking.append(
            {
                "rank": index,
                "user_id": str(row[0]),
                "display_name": user.display_name if user else "—",
                "phone_masked": user.phone_masked if user else "—",
                "role": user.role if user else "—",
                "input_tokens": int(row[1]),
                "output_tokens": int(row[2]),
                "total_tokens": int(row[3]),
                "call_count": int(row[4]),
            }
        )

    daily_rows = (
        await session.execute(
            select(
                shanghai_day,
                func.coalesce(func.sum(LlmTrace.total_tokens), 0),
                func.count(func.distinct(LlmTrace.user_id)),
            )
            .where(*filters)
            .group_by(shanghai_day)
            .order_by(shanghai_day)
        )
    ).all()
    daily_map = {
        row[0]: {"total_tokens": int(row[1]), "active_users": int(row[2])} for row in daily_rows
    }

    daily_totals: list[dict[str, Any]] = []
    day = start_date
    while day <= end_date:
        bucket = daily_map.get(day, {"total_tokens": 0, "active_users": 0})
        daily_totals.append(
            {
                "date": day.isoformat(),
                "total_tokens": bucket["total_tokens"],
                "active_users": bucket["active_users"],
            }
        )
        day += timedelta(days=1)

    return {
        "generated_at": now.isoformat(),
        "timezone": USAGE_TIMEZONE_LABEL,
        "filters": {
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "model": model or "",
            "limit": limit,
        },
        "summary": {
            "total_input_tokens": int(summary_row[0]),
            "total_output_tokens": int(summary_row[1]),
            "total_tokens": int(summary_row[2]),
            "call_count": int(summary_row[3]),
            "active_users": int(summary_row[4]),
            "top_model": top_model,
        },
        "ranking": ranking,
        "by_model": [
            {
                "model": str(row[0]),
                "total_tokens": int(row[1]),
                "call_count": int(row[2]),
            }
            for row in by_model_rows
        ],
        "daily_totals": daily_totals,
    }
