"""SQLAdmin 登录：环境变量账号，与用户端 parent/child JWT 完全隔离。"""

from __future__ import annotations

import hmac

from sqladmin.authentication import AuthenticationBackend
from starlette.requests import Request
from starlette.responses import RedirectResponse

from coco_admin.config import AdminSettings, get_admin_settings

# Session 内标记已登录的 key
_SESSION_FLAG = "coco_admin"


class AdminAuth(AuthenticationBackend):
    def __init__(self, settings: AdminSettings | None = None) -> None:
        resolved = settings or get_admin_settings()
        super().__init__(secret_key=resolved.admin_secret_key.get_secret_value())
        self._settings = resolved

    async def login(self, request: Request) -> bool:
        form = await request.form()
        username = str(form.get("username") or "").strip()
        password = str(form.get("password") or "")
        expected_user = self._settings.admin_username
        expected_pass = self._settings.admin_password.get_secret_value()
        # 恒定时间比较，降低口令比对侧信道
        user_ok = hmac.compare_digest(username, expected_user)
        pass_ok = hmac.compare_digest(password, expected_pass)
        if not (user_ok and pass_ok):
            return False
        request.session.update({_SESSION_FLAG: expected_user})
        return True

    async def logout(self, request: Request) -> bool:
        request.session.clear()
        return True

    async def authenticate(self, request: Request) -> bool | RedirectResponse:
        if request.session.get(_SESSION_FLAG):
            return True
        return False


def is_admin_authenticated(request: Request) -> bool:
    """供自定义 API 复用同一 session 登录态。"""
    return bool(request.session.get(_SESSION_FLAG))
