"""管理后台 FastAPI 入口（默认端口 8001，与用户 API 分离）。"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import RedirectResponse

from coco_admin import __version__
from coco_admin.config import AdminSettings, get_admin_settings
from coco_admin.database import dispose_admin_database, init_admin_database
from coco_admin.views import mount_admin


def create_app(settings: AdminSettings | None = None) -> FastAPI:
    resolved = settings or get_admin_settings()
    engine, _ = init_admin_database(resolved)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        yield
        await dispose_admin_database()

    app = FastAPI(
        title="Coco Admin",
        version=__version__,
        docs_url="/docs" if resolved.environment != "production" else None,
        redoc_url=None,
        lifespan=lifespan,
    )

    # 根路径跳转到后台首页
    @app.get("/", include_in_schema=False)
    async def root_redirect() -> RedirectResponse:
        return RedirectResponse(url="/admin", status_code=302)

    @app.get("/health", tags=["health"])
    async def health() -> dict[str, str]:
        return {"status": "ok", "service": "coco-admin"}

    # 统计 JSON 挂在 SQLAdmin 子应用：/admin/api/stats（需登录）
    mount_admin(app, engine, resolved)
    return app


app = create_app()
