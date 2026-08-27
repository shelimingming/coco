"""FastAPI 应用入口。"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from uuid import uuid4

import structlog
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

from coco import __version__
from coco.config import Settings, get_settings
from coco.database import dispose_database, get_session_factory, init_database
from coco.errors import register_exception_handlers
from coco.logging import configure_logging
from coco.modules.audio.router import router as audio_router
from coco.modules.auth.router import me_router
from coco.modules.auth.router import router as auth_router
from coco.modules.care.router import router as care_router
from coco.modules.conversations.router import router as conversations_router
from coco.modules.family.router import router as family_router
from coco.modules.health.router import router as health_router
from coco.modules.memories.router import router as memories_router
from coco.modules.messages.router import router as messages_router
from coco.modules.notifications.router import router as notifications_router
from coco.modules.reminders.router import router as reminders_router
from coco.modules.vision.router import router as vision_router
from coco.modules.voice.router import router as voice_router
from coco.scheduler import scheduler_loop


def _register_invite_short_link(app: FastAPI) -> None:
    """对外分享用 /i/{code}，302 到 Flutter Web hash 落地页。"""

    @app.get("/i/{code}")
    async def invite_short_link(code: str) -> RedirectResponse:
        token = code.strip()
        # 只接受 6–8 位 URL 安全字符，避免把任意路径转进前端
        if not (6 <= len(token) <= 8) or any(
            ch not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
            for ch in token
        ):
            raise HTTPException(status_code=404, detail="Not Found")
        return RedirectResponse(url=f"/index.html#/invite/{token}", status_code=302)


def _mount_web_static(app: FastAPI, settings: Settings) -> None:
    """一体部署时托管 Flutter Web；必须在 API 路由注册之后挂载。"""
    raw = (settings.web_static_dir or "").strip()
    if not raw:
        return
    root = Path(raw).expanduser().resolve()
    if not root.is_dir():
        raise RuntimeError(f"COCO_WEB_STATIC_DIR 不是目录：{root}")
    index = root / "index.html"
    if not index.is_file():
        raise RuntimeError(f"COCO_WEB_STATIC_DIR 缺少 index.html：{root}")

    def _safe_file(full_path: str) -> Path | None:
        if not full_path or full_path.endswith("/"):
            return None
        candidate = (root / full_path).resolve()
        try:
            candidate.relative_to(root)
        except ValueError:
            return None
        return candidate if candidate.is_file() else None

    def _web_file_response(path: Path) -> FileResponse:
        # html/js 文件名无内容 hash，禁止长期缓存，否则发版后仍看到旧页
        headers: dict[str, str] = {}
        if path.suffix.lower() in {".html", ".js", ".css", ".json"}:
            headers["Cache-Control"] = "no-cache, must-revalidate"
        return FileResponse(path, headers=headers)

    presentation = root / "presentation.html"

    @app.get("/")
    async def web_root() -> RedirectResponse:
        # 域名根路径默认进双端演示页；单端 App 仍用 /index.html
        if presentation.is_file():
            return RedirectResponse(url="/presentation.html", status_code=302)
        return RedirectResponse(url="/index.html", status_code=302)

    # 捕获前端资源与 go_router 深链；/health、/v1 已先注册，不会被盖住
    @app.get("/{full_path:path}")
    async def web_spa_or_asset(full_path: str) -> FileResponse:
        # 未知 API/文档路径保持 404，避免误返回 index.html
        head = full_path.split("/", 1)[0]
        if head in {"v1", "health", "docs", "redoc", "openapi.json"}:
            raise HTTPException(status_code=404, detail="Not Found")
        file_path = _safe_file(full_path)
        if file_path is not None:
            return _web_file_response(file_path)
        return _web_file_response(index)


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        request_id = request.headers.get("X-Request-ID") or str(uuid4())
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(
            request_id=request_id,
            path=request.url.path,
            method=request.method,
        )
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response


def create_app(settings: Settings | None = None) -> FastAPI:
    resolved = settings or get_settings()
    configure_logging(resolved.log_level)
    init_database(resolved)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        stop_event = asyncio.Event()
        # 测试环境不启动后台调度，避免干扰用例
        task: asyncio.Task[None] | None = None
        if resolved.environment != "test":
            factory = get_session_factory()
            task = asyncio.create_task(
                scheduler_loop(factory, resolved, stop_event=stop_event),
                name="reminder-scheduler",
            )
        yield
        stop_event.set()
        if task is not None:
            try:
                await asyncio.wait_for(task, timeout=5.0)
            except (TimeoutError, asyncio.CancelledError):
                task.cancel()
        await dispose_database()

    app = FastAPI(
        title="Coco Backend",
        version=__version__,
        docs_url="/docs" if resolved.environment != "production" else None,
        redoc_url=None,
        lifespan=lifespan,
    )

    allow_credentials = "*" not in resolved.cors_origins
    app.add_middleware(
        CORSMiddleware,
        allow_origins=resolved.cors_origins,
        allow_credentials=allow_credentials,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(RequestContextMiddleware)
    register_exception_handlers(app)

    app.include_router(health_router)
    app.include_router(auth_router)
    app.include_router(me_router)
    app.include_router(voice_router)
    app.include_router(vision_router)
    app.include_router(audio_router)
    app.include_router(family_router)
    app.include_router(reminders_router)
    app.include_router(memories_router)
    app.include_router(conversations_router)
    app.include_router(care_router)
    app.include_router(messages_router)
    app.include_router(notifications_router)
    # 邀请短链必须在 SPA 通配之前；纯 API 部署也可用
    _register_invite_short_link(app)
    # 静态站最后挂载，避免吞掉 /health、/v1、/docs
    _mount_web_static(app, resolved)
    return app


app = create_app()
