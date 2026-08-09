"""应用配置：统一使用 COCO_ 前缀，从 .env 读取。"""

from functools import lru_cache
from typing import Literal

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="COCO_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    environment: Literal["development", "staging", "production", "test"] = "development"
    log_level: str = "INFO"
    database_url: str = "postgresql+asyncpg://coco:coco_dev_password@127.0.0.1:5432/coco"

    auth_signing_key: SecretStr = SecretStr(
        "local-development-only-change-before-sharing-0123456789"
    )
    auth_hash_pepper: SecretStr = SecretStr(
        "local-development-pepper-change-me-0123456789abcdef"
    )
    auth_issuer: str = "coco-backend"
    auth_audience: str = "coco-ios"
    access_token_ttl_seconds: int = 3600
    refresh_token_ttl_days: int = 30

    # 短信：dev 固定码；后续可切 aliyun
    sms_provider: Literal["dev", "aliyun"] = "dev"
    dev_sms_code: SecretStr = SecretStr("246810")
    otp_ttl_seconds: int = 300
    otp_max_attempts: int = 5
    otp_request_limit_per_hour: int = 5

    cors_allowed_origins: str = "*"

    @field_validator("cors_allowed_origins", mode="before")
    @classmethod
    def _strip_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip()
        return value

    @property
    def cors_origins(self) -> list[str]:
        raw = self.cors_allowed_origins.strip()
        if raw == "*":
            return ["*"]
        return [item.strip() for item in raw.split(",") if item.strip()]

    def validate_runtime_safety(self) -> None:
        """非开发环境禁止使用开发短信与默认密钥。"""
        if self.environment in {"staging", "production"}:
            if self.sms_provider == "dev":
                raise RuntimeError("staging/production 禁止使用 COCO_SMS_PROVIDER=dev")
            signing = self.auth_signing_key.get_secret_value()
            pepper = self.auth_hash_pepper.get_secret_value()
            if "local-development" in signing or "local-development" in pepper:
                raise RuntimeError("staging/production 必须更换鉴权密钥与 pepper")


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.validate_runtime_safety()
    return settings
