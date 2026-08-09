"""应用配置：统一使用 COCO_ 前缀，从 .env 读取。"""

from functools import lru_cache
from typing import Literal

from pydantic import AliasChoices, Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="COCO_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        # 允许构造参数用字段名；env 仍认 AliasChoices 中的完整变量名
        populate_by_name=True,
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

    # 百炼实时语音：密钥只留服务端；无 Key 时应用照常启动，能力关闭
    aliyun_api_key: SecretStr | None = Field(
        default=None,
        validation_alias=AliasChoices("COCO_ALIYUN_API_KEY", "DASHSCOPE_API_KEY"),
    )
    aliyun_region: Literal["cn-beijing", "ap-southeast-1"] = "cn-beijing"
    realtime_model: str = "qwen-audio-3.0-realtime-plus"
    realtime_voice: str = "longanqian"

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

    @property
    def realtime_websocket_url(self) -> str:
        """Qwen-Audio Realtime WebSocket 基址（不含 model 查询参数）。"""
        if self.aliyun_region == "ap-southeast-1":
            return "wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime"
        return "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"

    @property
    def realtime_available(self) -> bool:
        """有可用阿里云 Key 时才对客户端声明实时能力。"""
        key = self.aliyun_api_key
        if key is None:
            return False
        return bool(key.get_secret_value().strip())

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
