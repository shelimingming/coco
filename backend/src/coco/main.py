"""FastAPI 应用入口。"""

from __future__ import annotations

from contextlib import asynccontextmanager
from collections.abc import AsyncIterator
from uuid import uuid4

import structlog
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

from coco import __version__
from coco.config import Settings, get_settings
from coco.database import dispose_database, init_database
from coco.errors import register_exception_handlers
from coco.logging import configure_logging
from coco.modules.auth.router import me_router, router as auth_router
from coco.modules.health.router import router as health_router


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
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
        yield
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
    return app


app = create_app()
