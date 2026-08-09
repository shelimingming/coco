"""运营总览自定义页（挂在 SQLAdmin 侧栏）。"""

from __future__ import annotations

from sqladmin import BaseView, expose
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from coco_admin.database import get_session_factory
from coco_admin.stats.service import collect_stats


class StatsAdminView(BaseView):
    name = "运营总览"
    icon = "fa-solid fa-chart-line"
    # 置顶分类，方便首屏进入
    category = "总览"

    @expose("/stats", methods=["GET"])
    async def stats_page(self, request: Request) -> Response:
        factory = get_session_factory()
        async with factory() as session:
            stats = await collect_stats(session)
        return await self.templates.TemplateResponse(
            request,
            "sqladmin/stats.html",
            {"stats": stats},
        )

    # 挂在 SQLAdmin 子应用下，路径为 /admin/api/stats，复用登录 session
    @expose("/api/stats", methods=["GET"])
    async def stats_api(self, request: Request) -> JSONResponse:
        factory = get_session_factory()
        async with factory() as session:
            stats = await collect_stats(session)
        return JSONResponse(stats)
