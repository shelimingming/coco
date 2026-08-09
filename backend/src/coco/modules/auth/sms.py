"""短信发送抽象：开发环境固定码，后续可接阿里云。"""

from __future__ import annotations

from typing import Protocol

from coco.config import Settings
from coco.errors import AppError


class SmsSender(Protocol):
    async def send_login_code(self, *, phone: str, code: str) -> None: ...


class DevSmsSender:
    """开发环境不真发短信，验证码由配置固定。"""

    async def send_login_code(self, *, phone: str, code: str) -> None:
        # 故意不打日志，避免验证码泄漏到日志
        return None


class AliyunSmsSender:
    """占位：后续接入阿里云短信时实现。"""

    async def send_login_code(self, *, phone: str, code: str) -> None:
        raise AppError(503, "auth.sms_unavailable", "短信服务尚未配置，请稍后再试。")


def build_sms_sender(settings: Settings) -> SmsSender:
    if settings.sms_provider == "dev":
        return DevSmsSender()
    if settings.sms_provider == "aliyun":
        return AliyunSmsSender()
    raise AppError(500, "auth.sms_misconfigured", "短信服务配置不正确。")


def resolve_login_code(settings: Settings) -> str:
    """当前仅支持开发固定码；接真实短信时改为随机 6 位。"""
    if settings.sms_provider == "dev":
        return settings.dev_sms_code.get_secret_value()
    # 预留：生产应生成随机码并交给真实 SmsSender
    import secrets

    return f"{secrets.randbelow(1_000_000):06d}"
