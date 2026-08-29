"""百度 BOS 适配层测试：默认 mock SDK；可选连真实桶。"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from pydantic import SecretStr

from coco.config import Settings
from coco.providers.bos_storage import (
    BosStorage,
    bos_available,
    build_bos_storage,
    get_bos_storage,
)


def _storage_with_mock_client() -> tuple[BosStorage, MagicMock]:
    # 构造时仍会建真实 BosClient，随即换成 mock，避免单测打外网
    storage = BosStorage(
        access_key_id=SecretStr("test-ak"),
        secret_access_key=SecretStr("test-sk"),
        endpoint="https://bj.bcebos.com",
        bucket="coco-oss",
    )
    client = MagicMock()
    storage._client = client
    return storage, client


def test_object_url_virtual_host() -> None:
    storage, _ = _storage_with_mock_client()
    assert storage.object_url("/daily/a.jpg") == "https://coco-oss.bj.bcebos.com/daily/a.jpg"


def test_object_url_strips_leading_slash_and_custom_bucket() -> None:
    storage, _ = _storage_with_mock_client()
    assert storage.object_url("x.png", bucket="other") == "https://other.bj.bcebos.com/x.png"


def test_endpoint_without_scheme_defaults_https() -> None:
    storage = BosStorage(
        access_key_id=SecretStr("ak"),
        secret_access_key=SecretStr("sk"),
        endpoint="bj.bcebos.com",
        bucket="coco-oss",
    )
    assert storage._endpoint == "https://bj.bcebos.com"
    assert storage.object_url("k") == "https://coco-oss.bj.bcebos.com/k"


def test_empty_bucket_raises() -> None:
    with pytest.raises(RuntimeError, match="bucket"):
        BosStorage(
            access_key_id=SecretStr("ak"),
            secret_access_key=SecretStr("sk"),
            endpoint="https://bj.bcebos.com",
            bucket="  ",
        )


def test_bos_available_requires_ak_sk_bucket() -> None:
    assert not bos_available(
        Settings(
            bos_access_key_id=None,
            bos_secret_access_key=SecretStr("sk"),
            bos_bucket="coco-oss",
        )
    )
    assert not bos_available(
        Settings(
            bos_access_key_id=SecretStr("ak"),
            bos_secret_access_key=SecretStr("sk"),
            bos_bucket="",
        )
    )
    assert bos_available(
        Settings(
            bos_access_key_id=SecretStr("ak"),
            bos_secret_access_key=SecretStr("sk"),
            bos_bucket="coco-oss",
        )
    )


def test_build_bos_storage_requires_config() -> None:
    with pytest.raises(RuntimeError, match="BOS 未配置"):
        build_bos_storage(Settings(bos_access_key_id=None, bos_secret_access_key=None))


@pytest.mark.asyncio
async def test_put_bytes_get_bytes_delete_roundtrip_mocked() -> None:
    storage, client = _storage_with_mock_client()
    client.put_object.return_value = SimpleNamespace(etag='"abc"')
    client.get_object_as_string.return_value = b"hello"

    put = await storage.put_bytes(
        "/coco/dev/t.txt",
        b"hello",
        content_type="text/plain",
    )
    assert put.key == "coco/dev/t.txt"
    assert put.etag == '"abc"'
    assert put.url.endswith("/coco/dev/t.txt")
    client.put_object.assert_called_once()
    args, kwargs = client.put_object.call_args
    assert args[0] == "coco-oss"
    assert args[1] == "coco/dev/t.txt"
    assert args[3] == 5
    assert kwargs.get("content_type") == "text/plain"

    data = await storage.get_bytes("coco/dev/t.txt")
    assert data == b"hello"

    await storage.delete("coco/dev/t.txt")
    client.delete_object.assert_called_once_with("coco-oss", "coco/dev/t.txt")


@pytest.mark.asyncio
async def test_exists_true_and_false() -> None:
    from baidubce.exception import BceError

    storage, client = _storage_with_mock_client()
    client.get_object_meta_data.return_value = SimpleNamespace()
    assert await storage.exists("a.txt") is True

    client.get_object_meta_data.side_effect = BceError("missing")
    assert await storage.exists("missing.txt") is False


@pytest.mark.asyncio
async def test_list_objects_maps_fields() -> None:
    storage, client = _storage_with_mock_client()
    client.list_objects.return_value = SimpleNamespace(
        contents=[
            SimpleNamespace(
                key="p/a.jpg",
                size=12,
                last_modified="2026-08-30T00:00:00Z",
                etag='"e1"',
            )
        ]
    )
    items = await storage.list_objects(prefix="p/")
    assert len(items) == 1
    assert items[0].key == "p/a.jpg"
    assert items[0].size == 12
    assert items[0].etag == '"e1"'


@pytest.mark.asyncio
async def test_presigned_url_decodes_bytes() -> None:
    storage, client = _storage_with_mock_client()
    client.generate_pre_signed_url.return_value = b"https://signed.example/obj"

    url = await storage.presigned_url("obj", expiration_seconds=120)
    assert url == "https://signed.example/obj"
    _, kwargs = client.generate_pre_signed_url.call_args
    assert kwargs["expiration_in_seconds"] == 120


@pytest.mark.asyncio
async def test_presigned_url_rejects_bad_method() -> None:
    storage, _ = _storage_with_mock_client()
    with pytest.raises(ValueError, match="不支持的 HTTP 方法"):
        await storage.presigned_url("obj", http_method="FOO")


@pytest.mark.bos
@pytest.mark.asyncio
async def test_bos_live_put_get_delete() -> None:
    """连真实 coco-oss；密钥无效或未配置时跳过，不挡日常 CI。"""
    from baidubce.exception import BceHttpClientError, BceServerError

    from coco.config import get_settings
    from coco.providers.bos_storage import get_bos_storage

    get_settings.cache_clear()
    get_bos_storage.cache_clear()

    settings = get_settings()
    if not settings.bos_available:
        pytest.skip("BOS 未配置，跳过真实连通性测试")

    bos = get_bos_storage()
    key = "coco/dev/pytest-smoke.txt"
    payload = b"coco bos pytest"

    try:
        put = await bos.put_bytes(key, payload, content_type="text/plain")
        assert put.key == key
        assert await bos.exists(key) is True
        assert await bos.get_bytes(key) == payload
        url = await bos.presigned_url(key, expiration_seconds=300)
        assert "coco-oss" in url or "bcebos.com" in url
    except (BceHttpClientError, BceServerError) as exc:
        pytest.skip(f"BOS 真实调用失败（可能密钥无效）: {exc}")
    finally:
        try:
            await bos.delete(key)
        except Exception:
            # 清理失败不影响断言结果
            pass
