"""FastAPI 应用入口。"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from uuid import uuid4

import structlog
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

from coco import __version__
from coco.config import Settings, get_settings
from coco.database import dispose_database, get_session_factory, init_database
from coco.errors import register_exception_handlers
from coco.logging import configure_logging
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
from coco.modules.voice.router import router as voice_router
from coco.scheduler import scheduler_loop


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
    app.include_router(family_router)
    app.include_router(reminders_router)
    app.include_router(memories_router)
    app.include_router(conversations_router)
    app.include_router(care_router)
    app.include_router(messages_router)
    app.include_router(notifications_router)
    return app


app = create_app()
