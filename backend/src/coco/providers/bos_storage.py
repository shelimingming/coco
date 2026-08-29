"""百度智能云 BOS 对象存储适配层。

密钥与协议只留在此包；业务侧通过 BosStorage 上传/下载/签名 URL。
SDK 为同步调用，统一用 asyncio.to_thread 避免堵住事件循环。
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass
from functools import lru_cache
from io import BytesIO
from typing import BinaryIO

from pydantic import SecretStr

from coco.config import Settings, get_settings

logger = logging.getLogger(__name__)


@dataclass(slots=True, frozen=True)
class BosObjectInfo:
    """列出对象时的精简元数据。"""

    key: str
    size: int
    last_modified: str | None
    etag: str | None


@dataclass(slots=True, frozen=True)
class BosPutResult:
    key: str
    etag: str | None
    # virtual-host 风格外链；是否可匿名访问取决于桶/对象 ACL
    url: str


class BosStorage:
    """面向业务的 BOS 工具；默认操作配置中的 bucket。"""

    def __init__(
        self,
        *,
        access_key_id: SecretStr,
        secret_access_key: SecretStr,
        endpoint: str,
        bucket: str,
    ) -> None:
        # 延迟导入：无 Key 时不应在 import 阶段强依赖 SDK
        from baidubce.auth.bce_credentials import BceCredentials
        from baidubce.bce_client_configuration import BceClientConfiguration
        from baidubce.services.bos.bos_client import BosClient

        cleaned_endpoint = endpoint.strip().rstrip("/")
        if not cleaned_endpoint.startswith(("http://", "https://")):
            cleaned_endpoint = f"https://{cleaned_endpoint}"

        config = BceClientConfiguration(
            credentials=BceCredentials(
                access_key_id.get_secret_value().strip(),
                secret_access_key.get_secret_value().strip(),
            ),
            endpoint=cleaned_endpoint,
        )
        self._client = BosClient(config)
        self._endpoint = cleaned_endpoint
        self.bucket = bucket.strip()
        if not self.bucket:
            raise RuntimeError("BOS bucket 不能为空")

    def object_url(self, key: str, *, bucket: str | None = None) -> str:
        """拼 virtual-host 风格 URL（不含签名）。"""
        cleaned = key.lstrip("/")
        host = self._endpoint.removeprefix("https://").removeprefix("http://")
        scheme = "https" if self._endpoint.startswith("https://") else "http"
        return f"{scheme}://{(bucket or self.bucket)}.{host}/{cleaned}"

    async def put_bytes(
        self,
        key: str,
        data: bytes,
        *,
        content_type: str | None = None,
        bucket: str | None = None,
    ) -> BosPutResult:
        """上传二进制内容。"""
        target = bucket or self.bucket
        cleaned = key.lstrip("/")

        def _run() -> BosPutResult:
            # put_object 吃二进制流；from_string 面向文本
            response = self._client.put_object(
                target,
                cleaned,
                BytesIO(data),
                len(data),
                content_type=content_type,
            )
            etag = getattr(response, "metadata", None)
            etag_value = getattr(etag, "etag", None) if etag is not None else None
            if etag_value is None:
                etag_value = getattr(response, "etag", None)
            return BosPutResult(
                key=cleaned,
                etag=etag_value,
                url=self.object_url(cleaned, bucket=target),
            )

        result = await asyncio.to_thread(_run)
        logger.info("bos_put_bytes bucket=%s key=%s size=%s", target, cleaned, len(data))
        return result

    async def put_file(
        self,
        key: str,
        file_path: str,
        *,
        content_type: str | None = None,
        bucket: str | None = None,
    ) -> BosPutResult:
        """从本地路径上传文件。"""
        target = bucket or self.bucket
        cleaned = key.lstrip("/")

        def _run() -> BosPutResult:
            response = self._client.put_object_from_file(
                target,
                cleaned,
                file_path,
                content_type=content_type,
            )
            etag = getattr(response, "metadata", None)
            etag_value = getattr(etag, "etag", None) if etag is not None else None
            if etag_value is None:
                etag_value = getattr(response, "etag", None)
            return BosPutResult(
                key=cleaned,
                etag=etag_value,
                url=self.object_url(cleaned, bucket=target),
            )

        result = await asyncio.to_thread(_run)
        logger.info("bos_put_file bucket=%s key=%s path=%s", target, cleaned, file_path)
        return result

    async def put_stream(
        self,
        key: str,
        stream: BinaryIO,
        content_length: int,
        *,
        content_type: str | None = None,
        bucket: str | None = None,
    ) -> BosPutResult:
        """从文件流上传（需已知长度）。"""
        target = bucket or self.bucket
        cleaned = key.lstrip("/")

        def _run() -> BosPutResult:
            response = self._client.put_object(
                target,
                cleaned,
                stream,
                content_length,
                content_type=content_type,
            )
            etag = getattr(response, "metadata", None)
            etag_value = getattr(etag, "etag", None) if etag is not None else None
            if etag_value is None:
                etag_value = getattr(response, "etag", None)
            return BosPutResult(
                key=cleaned,
                etag=etag_value,
                url=self.object_url(cleaned, bucket=target),
            )

        result = await asyncio.to_thread(_run)
        logger.info("bos_put_stream bucket=%s key=%s size=%s", target, cleaned, content_length)
        return result

    async def get_bytes(self, key: str, *, bucket: str | None = None) -> bytes:
        """下载对象为 bytes。"""
        target = bucket or self.bucket
        cleaned = key.lstrip("/")

        def _run() -> bytes:
            raw = self._client.get_object_as_string(target, cleaned)
            if isinstance(raw, bytes):
                return raw
            return raw.encode("utf-8") if isinstance(raw, str) else bytes(raw)

        data = await asyncio.to_thread(_run)
        logger.info("bos_get_bytes bucket=%s key=%s size=%s", target, cleaned, len(data))
        return data

    async def get_to_file(
        self,
        key: str,
        file_path: str,
        *,
        bucket: str | None = None,
    ) -> str:
        """下载到本地文件，返回路径。"""
        target = bucket or self.bucket
        cleaned = key.lstrip("/")

        def _run() -> None:
            self._client.get_object_to_file(target, cleaned, file_path)

        await asyncio.to_thread(_run)
        logger.info("bos_get_to_file bucket=%s key=%s path=%s", target, cleaned, file_path)
        return file_path

    async def delete(self, key: str, *, bucket: str | None = None) -> None:
        """删除对象。"""
        target = bucket or self.bucket
        cleaned = key.lstrip("/")

        def _run() -> None:
            self._client.delete_object(target, cleaned)

        await asyncio.to_thread(_run)
        logger.info("bos_delete bucket=%s key=%s", target, cleaned)

    async def exists(self, key: str, *, bucket: str | None = None) -> bool:
        """对象是否存在（通过读元数据探测）。"""
        from baidubce import exception as bce_exception

        target = bucket or self.bucket
        cleaned = key.lstrip("/")

        def _run() -> bool:
            try:
                self._client.get_object_meta_data(target, cleaned)
                return True
            except bce_exception.BceError:
                return False

        return await asyncio.to_thread(_run)

    async def list_objects(
        self,
        *,
        prefix: str = "",
        max_keys: int = 1000,
        marker: str | None = None,
        bucket: str | None = None,
    ) -> list[BosObjectInfo]:
        """列出 bucket 内对象（单页，最多 max_keys）。"""
        target = bucket or self.bucket

        def _run() -> list[BosObjectInfo]:
            response = self._client.list_objects(
                target,
                prefix=prefix,
                marker=marker,
                max_keys=max_keys,
            )
            items: list[BosObjectInfo] = []
            for obj in response.contents or []:
                items.append(
                    BosObjectInfo(
                        key=obj.key,
                        size=int(getattr(obj, "size", 0) or 0),
                        last_modified=getattr(obj, "last_modified", None),
                        etag=getattr(obj, "etag", None),
                    )
                )
            return items

        return await asyncio.to_thread(_run)

    async def presigned_url(
        self,
        key: str,
        *,
        expiration_seconds: int = 3600,
        bucket: str | None = None,
        http_method: str = "GET",
    ) -> str:
        """生成临时签名 URL，供客户端短期读写。"""
        from baidubce.http import http_methods

        target = bucket or self.bucket
        cleaned = key.lstrip("/")
        method = http_method.upper()
        method_const = getattr(http_methods, method, None)
        if method_const is None:
            raise ValueError(f"不支持的 HTTP 方法: {http_method}")
        # SDK 以绝对时间戳为基准，expiration_in_seconds 为相对有效期
        timestamp = int(time.time())

        def _run() -> str:
            url = self._client.generate_pre_signed_url(
                target,
                cleaned,
                timestamp,
                expiration_in_seconds=expiration_seconds,
                httpmethod=method_const,
            )
            if isinstance(url, bytes):
                return url.decode("utf-8")
            return str(url)

        return await asyncio.to_thread(_run)

    def ensure_web_read_cors(self) -> None:
        """为 Flutter Web / 浏览器直连签名 URL 配置桶 CORS（私有桶仍需签名）。"""
        # 允许本机调试与任意生产域；GET/HEAD 足够 Image.network
        rules = [
            {
                "allowedOrigins": ["*"],
                "allowedMethods": ["GET", "HEAD"],
                "allowedHeaders": ["*"],
                "allowedExposeHeaders": ["ETag", "Content-Length", "Content-Type"],
                "maxAgeSeconds": 3600,
            }
        ]

        def _run() -> None:
            self._client.put_bucket_cors(self.bucket, rules)

        # 同步调用：启动或运维时一次性写入
        _run()
        logger.info("bos_cors_ensured bucket=%s", self.bucket)

    async def ensure_web_read_cors_async(self) -> None:
        await asyncio.to_thread(self.ensure_web_read_cors)


def bos_available(settings: Settings) -> bool:
    """AK/SK/bucket 齐全时才认为可用。"""
    return settings.bos_available


def build_bos_storage(settings: Settings, *, ensure_cors: bool = False) -> BosStorage:
    """从 Settings 构造客户端；未配置时抛出明确错误。"""
    if not settings.bos_available:
        raise RuntimeError(
            "BOS 未配置：请在 .env 设置 COCO_BOS_ACCESS_KEY_ID / "
            "COCO_BOS_SECRET_ACCESS_KEY / COCO_BOS_BUCKET"
        )
    assert settings.bos_access_key_id is not None
    assert settings.bos_secret_access_key is not None
    storage = BosStorage(
        access_key_id=settings.bos_access_key_id,
        secret_access_key=settings.bos_secret_access_key,
        endpoint=settings.bos_endpoint,
        bucket=settings.bos_bucket,
    )
    if ensure_cors:
        try:
            storage.ensure_web_read_cors()
        except Exception:
            logger.warning("bos_cors_ensure_failed bucket=%s", storage.bucket, exc_info=True)
    return storage


@lru_cache
def get_bos_storage() -> BosStorage:
    """进程内复用同一 BosClient（Settings 变更后需重启）。"""
    # 首次取用时写一次 CORS，保证 Web Image.network 不被浏览器拦
    return build_bos_storage(get_settings(), ensure_cors=True)
