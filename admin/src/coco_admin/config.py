"""管理后台配置：与用户端 JWT 隔离，账号仅走环境变量。"""

from functools import lru_cache
from typing import Literal

from pydantic import AliasChoices, Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class AdminSettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        populate_by_name=True,
    )

    environment: Literal["development", "staging", "production", "test"] = Field(
        default="development",
        validation_alias=AliasChoices("COCO_ADMIN_ENVIRONMENT", "COCO_ENVIRONMENT"),
    )
    log_level: str = Field(
        default="INFO",
        validation_alias=AliasChoices("COCO_ADMIN_LOG_LEVEL", "COCO_LOG_LEVEL"),
    )
    # 与 backend 共用同一库；优先读 COCO_DATABASE_URL
    database_url: str = Field(
        default="postgresql+asyncpg://coco:coco_dev_password@127.0.0.1:5432/coco",
        validation_alias=AliasChoices("COCO_DATABASE_URL", "COCO_ADMIN_DATABASE_URL"),
    )

    admin_username: str = Field(
        default="admin",
        validation_alias="COCO_ADMIN_USERNAME",
    )
    # 仅本地默认；生产必须通过环境变量覆盖
    admin_password: SecretStr = Field(
        default=SecretStr("coco-admin-dev"),
        validation_alias="COCO_ADMIN_PASSWORD",
    )
    # Session 签名密钥（SQLAdmin AuthenticationBackend）
    admin_secret_key: SecretStr = Field(
        default=SecretStr("local-admin-session-secret-change-me-0123456789"),
        validation_alias="COCO_ADMIN_SECRET_KEY",
    )

    @field_validator("admin_username")
    @classmethod
    def _strip_username(cls, value: str) -> str:
        return value.strip()

    def validate_runtime_safety(self) -> None:
        """非开发环境禁止使用默认口令与 session 密钥。"""
        if self.environment in {"staging", "production"}:
            password = self.admin_password.get_secret_value()
            secret = self.admin_secret_key.get_secret_value()
            if password in {"coco-admin-dev", "admin", "admin123"}:
                raise RuntimeError("staging/production 必须设置强 COCO_ADMIN_PASSWORD")
            if "local-admin-session" in secret or "change-me" in secret:
                raise RuntimeError("staging/production 必须更换 COCO_ADMIN_SECRET_KEY")


@lru_cache
def get_admin_settings() -> AdminSettings:
    settings = AdminSettings()
    settings.validate_runtime_safety()
    return settings
