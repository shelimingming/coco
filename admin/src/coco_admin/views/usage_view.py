"""用量统计自定义页（挂在 SQLAdmin 侧栏）。"""

from __future__ import annotations

from datetime import date, datetime

from sqladmin import BaseView, expose
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from coco_admin.database import get_session_factory
from coco_admin.usage.pricing import attach_cost_estimates
from coco_admin.usage.service import CST, collect_usage_stats, list_usage_models


def _cst_today() -> date:
    return datetime.now(CST).date()


def _parse_date(raw: str | None, default: date) -> date:
    if not raw:
        return default
    try:
        return date.fromisoformat(raw.strip())
    except ValueError:
        return default


class UsageAdminView(BaseView):
    name = "用量统计"
    icon = "fa-solid fa-coins"
    category = "总览"

    @expose("/usage", methods=["GET"])
    async def usage_page(self, request: Request) -> Response:
        today = _cst_today()
        start_date = _parse_date(request.query_params.get("start_date"), today)
        end_date = _parse_date(request.query_params.get("end_date"), today)
        model = (request.query_params.get("model") or "").strip() or None

        factory = get_session_factory()
        async with factory() as session:
            stats = await collect_usage_stats(
                session,
                start_date=start_date,
                end_date=end_date,
                model=model,
            )
            models = await list_usage_models(session)

        stats = attach_cost_estimates(
            stats,
            user_model_usage=stats.pop("user_model_usage", None),
        )

        debug_hours = UsageAdminView.debug_hours_for_range(start_date, end_date)

        return await self.templates.TemplateResponse(
            request,
            "sqladmin/usage.html",
            {
                "stats": stats,
                "models": models,
                "start_date": start_date.isoformat(),
                "end_date": end_date.isoformat(),
                "model": model or "",
                "debug_hours": debug_hours,
            },
        )

    @expose("/api/usage", methods=["GET"])
    async def usage_api(self, request: Request) -> JSONResponse:
        today = _cst_today()
        start_date = _parse_date(request.query_params.get("start_date"), today)
        end_date = _parse_date(request.query_params.get("end_date"), today)
        model = (request.query_params.get("model") or "").strip() or None

        factory = get_session_factory()
        async with factory() as session:
            stats = await collect_usage_stats(
                session,
                start_date=start_date,
                end_date=end_date,
                model=model,
            )
        stats = attach_cost_estimates(
            stats,
            user_model_usage=stats.pop("user_model_usage", None),
        )
        return JSONResponse(stats)

    @staticmethod
    def debug_hours_for_range(start_date: date, end_date: date) -> int:
        """链到模型调试页时，把日期范围换算为近 N 小时。"""
        today = _cst_today()
        span_days = max(1, (min(end_date, today) - start_date).days + 1)
        hours = span_days * 24
        if hours <= 24:
            return 24
        if hours <= 168:
            return 168
        if hours <= 720:
            return 720
        return 0
