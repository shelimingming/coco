"""统一业务错误与 FastAPI 异常处理。"""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class AppError(Exception):
    """业务可预期错误，message 可直接展示给用户。"""

    def __init__(self, status_code: int, code: str, message: str) -> None:
        self.status_code = status_code
        self.code = code
        self.message = message
        super().__init__(message)


def error_body(code: str, message: str) -> dict[str, Any]:
    return {"error": {"code": code, "message": message}}


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error_handler(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content=error_body(exc.code, exc.message),
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        detail = exc.detail
        if isinstance(detail, dict) and "code" in detail and "message" in detail:
            body = error_body(str(detail["code"]), str(detail["message"]))
        else:
            body = error_body("http.error", str(detail))
        return JSONResponse(status_code=exc.status_code, content=body)

    @app.exception_handler(RequestValidationError)
    async def _validation_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
        # 只暴露简短校验失败，避免把内部字段堆给客户端
        return JSONResponse(
            status_code=422,
            content=error_body("request.invalid", "请求参数不正确，请检查后重试。"),
        )

    @app.exception_handler(Exception)
    async def _unhandled_handler(_: Request, __: Exception) -> JSONResponse:
        return JSONResponse(
            status_code=500,
            content=error_body("server.error", "服务暂时出了点问题，请稍后再试。"),
        )
