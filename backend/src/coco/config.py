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
    auth_hash_pepper: SecretStr = SecretStr("local-development-pepper-change-me-0123456789abcdef")
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

    # Docker 一体部署：指向 Flutter Web 构建目录；空则不托管静态站
    web_static_dir: str | None = None

    # 百炼：密钥只留服务端；无 Key 时应用照常启动，实时/文本/识图/生图能力关闭或降级
    # 模型名均可在 .env 用 COCO_*_MODEL 覆盖
    aliyun_api_key: SecretStr | None = Field(
        default=None,
        validation_alias=AliasChoices("COCO_ALIYUN_API_KEY", "DASHSCOPE_API_KEY"),
    )
    aliyun_region: Literal["cn-beijing", "ap-southeast-1"] = "cn-beijing"
    realtime_model: str = "qwen-audio-3.0-realtime-plus"
    realtime_voice: str = "longanqian"
    # 文本模型：报平安转译、会话标题、语音联网搜索等无状态请求
    text_model: str = "qwen-plus"
    # 语音 web_search：走文本模型 enable_search；关或无 Key 时工具降级话术
    web_search_enabled: bool = True
    web_search_timeout_seconds: float = 30.0
    # 识图模型：须支持 Image 输入；qwen-plus 纯文本不可用
    vision_model: str = "qwen3.7-plus"
    # 文生图：万相 wan2.7-image（快）/ wan2.7-image-pro（可 4K）/ wan2.6-t2i 等
    image_model: str = "wan2.7-image"
    # 识图追问外壳：独立 ASR / TTS（非 Realtime）
    asr_model: str = "qwen-audio-3.0-asr-flash"
    tts_model: str = "qwen3-tts-flash"
    tts_voice: str = "Cherry"

    # Mem0 长期记忆：自托管 OSS + pgvector；无 Key 或关闭时读写降级为空
    mem0_enabled: bool = True
    mem0_embedding_model: str = "text-embedding-v4"
    mem0_embedding_dims: int = 1024
    mem0_collection_name: str = "coco_memories"
    # SQLite 变更历史；容器内需指向可写路径
    mem0_history_db_path: str = ".mem0/history.db"
    mem0_inject_limit: int = 20
    mem0_search_limit: int = 5
    # pgvector 连接池（AsyncMemory 并发下过小易耗尽）
    mem0_pg_minconn: int = 1
    mem0_pg_maxconn: int = 20

    # 提醒调度：第二次提醒 / 升级通知子女的间隔（分钟）
    reminder_second_delay_minutes: int = 30
    reminder_escalate_delay_minutes: int = 30
    reminder_scan_interval_seconds: int = 30
    # MVP 固定本地时区，老人说「晚上八点」按此时区解释
    local_timezone: str = "Asia/Shanghai"

    # 对外短链域名，用于拼邀请链接；生产设为 https://coco.xyfit.top
    public_base_url: str = "http://127.0.0.1:8000"
    # 免鉴权预览接口按 IP 限流，避免穷举 8 位码
    invite_preview_limit_per_hour: int = 30

    # 调试：把每次大模型调用写入 llm_traces，供运营后台按用户排查
    llm_trace_enabled: bool = True

    # 百度 BOS：密钥只留服务端；未配置时业务可降级跳过对象存储
    bos_access_key_id: SecretStr | None = None
    bos_secret_access_key: SecretStr | None = None
    bos_endpoint: str = "https://bj.bcebos.com"
    bos_bucket: str = "coco-oss"
    # 列表/设置返回的签名 URL 有效期（秒）
    bos_url_ttl_seconds: int = 3600

    @property
    def bos_available(self) -> bool:
        """AK/SK 与 bucket 齐全时才认为 BOS 可用。"""
        ak = self.bos_access_key_id
        sk = self.bos_secret_access_key
        if ak is None or sk is None:
            return False
        if not ak.get_secret_value().strip() or not sk.get_secret_value().strip():
            return False
        return bool(self.bos_bucket.strip())

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
    def aliyun_http_base_url(self) -> str:
        """百炼 HTTP API 基址（ASR/TTS 等非 compatible-mode 接口）。"""
        if self.aliyun_region == "ap-southeast-1":
            return "https://dashscope-intl.aliyuncs.com"
        return "https://dashscope.aliyuncs.com"

    @property
    def aliyun_compatible_base_url(self) -> str:
        """百炼 OpenAI 兼容模式基址（文本 / embedding / Mem0）。"""
        return f"{self.aliyun_http_base_url}/compatible-mode/v1"

    @property
    def realtime_available(self) -> bool:
        """有可用阿里云 Key 时才对客户端声明实时能力。"""
        key = self.aliyun_api_key
        if key is None:
            return False
        return bool(key.get_secret_value().strip())

    @property
    def mem0_available(self) -> bool:
        """Mem0 需要开关打开且有百炼 Key。"""
        return self.mem0_enabled and self.realtime_available

    def mem0_pg_connection_string(self) -> str:
        """把 asyncpg URL 转成 psycopg 连接串。

        search_path 必须含 public：pgvector 的 vector 类型通常装在 public，
        只写 coco 会导致 type \"vector\" does not exist，记忆静默写失败。
        表仍优先落在 coco（排在 search_path 最前）。
        """
        raw = self.database_url.replace("postgresql+asyncpg://", "postgresql://", 1)
        sep = "&" if "?" in raw else "?"
        return f"{raw}{sep}options=-csearch_path%3Dcoco%2Cpublic"

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
