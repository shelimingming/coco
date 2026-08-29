"""阿里云百炼万相文生图（DashScope multimodal-generation）。

默认模型 wan2.7-image；可用 COCO_IMAGE_MODEL 切到 wan2.7-image-pro / wan2.6-t2i 等。
返回的图片 URL 由百炼临时托管（约 24 小时），服务端不落盘、不转存。
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

import httpx
from pydantic import SecretStr

from coco.observability.llm_trace import PURPOSE_IMAGE_GENERATE, record_llm_trace

logger = logging.getLogger(__name__)

# 同步请求可能较慢（思考模式 / 高分辨率）
_DEFAULT_TIMEOUT = 120.0
_ASYNC_POLL_INTERVAL = 2.0
_ASYNC_POLL_MAX_SECONDS = 180.0


@dataclass(slots=True)
class GeneratedImage:
    url: str


@dataclass(slots=True)
class ImageGenerateResult:
    images: list[GeneratedImage]
    model: str
    size: str | None
    usage: dict[str, Any] | None = None


class WanImageClient:
    def __init__(
        self,
        *,
        api_key: SecretStr,
        model: str,
        base_url: str,
        timeout_seconds: float = _DEFAULT_TIMEOUT,
    ) -> None:
        self._api_key = api_key
        self.model = model
        self.base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds

    async def generate(
        self,
        *,
        prompt: str,
        negative_prompt: str | None = None,
        size: str | None = None,
        n: int = 1,
        watermark: bool = False,
        seed: int | None = None,
        thinking_mode: bool | None = None,
        prompt_extend: bool | None = None,
        reference_images: list[str] | None = None,
    ) -> ImageGenerateResult:
        """文生图 / 多图参考生图：content 可含 image + text。"""
        cleaned = prompt.strip()
        if not cleaned:
            raise RuntimeError("生图提示词不能为空")
        if n < 1 or n > 4:
            raise RuntimeError("生图张数 n 须在 1～4")

        content: list[dict[str, str]] = []
        for raw in reference_images or []:
            url = (raw or "").strip()
            if url:
                content.append({"image": url})
        content.append({"text": cleaned})

        parameters = self._build_parameters(
            size=size,
            n=n,
            watermark=watermark,
            seed=seed,
            negative_prompt=negative_prompt,
            thinking_mode=thinking_mode,
            prompt_extend=prompt_extend,
            has_reference=bool(reference_images),
        )
        payload: dict[str, Any] = {
            "model": self.model,
            "input": {
                "messages": [
                    {
                        "role": "user",
                        "content": content,
                    }
                ]
            },
            "parameters": parameters,
        }
        headers = {
            "Authorization": f"Bearer {self._api_key.get_secret_value()}",
            "Content-Type": "application/json",
        }
        started = datetime.now(UTC)
        t0 = time.perf_counter()
        try:
            data = await self._call_sync_or_async(payload=payload, headers=headers)
            result = parse_image_generate_response(data, model=self.model)
            await record_llm_trace(
                purpose=PURPOSE_IMAGE_GENERATE,
                modality="image",
                model=self.model,
                status="ok",
                latency_ms=int((time.perf_counter() - t0) * 1000),
                request_json=_trace_request(payload),
                response_json={
                    "image_count": len(result.images),
                    "size": result.size,
                    # URL 会过期，调试只记是否有图，不落完整签名链
                    "has_urls": bool(result.images),
                },
                usage_json=result.usage,
                started_at=started,
            )
            return result
        except Exception as exc:
            await record_llm_trace(
                purpose=PURPOSE_IMAGE_GENERATE,
                modality="image",
                model=self.model,
                status="error",
                latency_ms=int((time.perf_counter() - t0) * 1000),
                request_json=_trace_request(payload),
                error_message=str(exc),
                started_at=started,
            )
            raise

    def _build_parameters(
        self,
        *,
        size: str | None,
        n: int,
        watermark: bool,
        seed: int | None,
        negative_prompt: str | None,
        thinking_mode: bool | None,
        prompt_extend: bool | None,
        has_reference: bool = False,
    ) -> dict[str, Any]:
        params: dict[str, Any] = {
            "n": n,
            "watermark": watermark,
        }
        # 有参考图时用 1K/2K 规格字符串更稳；像素串留给纯文生图
        if has_reference:
            resolved_size = (size or "").strip() or "1K"
            if "*" in resolved_size or "x" in resolved_size.lower():
                resolved_size = "1K"
        else:
            resolved_size = (size or "").strip() or self._default_size()
        params["size"] = resolved_size
        if seed is not None:
            params["seed"] = seed

        model_l = self.model.lower()
        # wan2.6-t2i 走 prompt_extend / negative_prompt；2.7 走 thinking_mode
        if "t2i" in model_l or model_l.startswith("wanx") or "wan2.6" in model_l:
            params["prompt_extend"] = True if prompt_extend is None else prompt_extend
            neg = (negative_prompt or "").strip()
            if neg:
                params["negative_prompt"] = neg
        else:
            # 有参考图时默认关思考，加快多图参考生成
            if thinking_mode is None:
                params["thinking_mode"] = not has_reference
            else:
                params["thinking_mode"] = thinking_mode
            neg = (negative_prompt or "").strip()
            if neg:
                # 部分 2.7 部署也接受 negative_prompt；有则透传
                params["negative_prompt"] = neg
        return params

    def _default_size(self) -> str:
        model_l = self.model.lower()
        if "wan2.7" in model_l:
            return "2K"
        if "t2i" in model_l or "wan2.6" in model_l:
            return "1280*1280"
        return "2K"

    async def _call_sync_or_async(
        self,
        *,
        payload: dict[str, Any],
        headers: dict[str, str],
    ) -> dict[str, Any]:
        sync_url = f"{self.base_url}/api/v1/services/aigc/multimodal-generation/generation"
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(sync_url, headers=headers, json=payload)
            # 经典域名上部分账号/模型仅支持异步
            if response.status_code == 400 and _requires_async(response):
                return await self._generate_async(client, payload=payload, headers=headers)
            if response.status_code >= 400:
                raise RuntimeError(_format_dashscope_error(response))
            data = response.json()
            if isinstance(data, dict) and data.get("code"):
                # 业务错误偶发放在 200 body
                if _message_requires_async(str(data.get("message") or "")):
                    return await self._generate_async(client, payload=payload, headers=headers)
                raise RuntimeError(_format_body_error(data))
            if not isinstance(data, dict):
                raise RuntimeError("生图模型返回格式异常")
            return data

    async def _generate_async(
        self,
        client: httpx.AsyncClient,
        *,
        payload: dict[str, Any],
        headers: dict[str, str],
    ) -> dict[str, Any]:
        """异步创建任务后轮询 /api/v1/tasks/{task_id}。"""
        async_headers = {**headers, "X-DashScope-Async": "enable"}
        create_url = f"{self.base_url}/api/v1/services/aigc/image-generation/generation"
        create_resp = await client.post(create_url, headers=async_headers, json=payload)
        if create_resp.status_code >= 400:
            raise RuntimeError(_format_dashscope_error(create_resp))
        create_body = create_resp.json()
        if not isinstance(create_body, dict):
            raise RuntimeError("生图异步任务创建失败")
        output = create_body.get("output")
        task_id = output.get("task_id") if isinstance(output, dict) else None
        if not isinstance(task_id, str) or not task_id.strip():
            raise RuntimeError(
                _format_body_error(create_body) if create_body.get("code") else "生图未返回 task_id"
            )

        deadline = time.perf_counter() + _ASYNC_POLL_MAX_SECONDS
        task_url = f"{self.base_url}/api/v1/tasks/{task_id}"
        while time.perf_counter() < deadline:
            await asyncio.sleep(_ASYNC_POLL_INTERVAL)
            poll = await client.get(task_url, headers=headers)
            if poll.status_code >= 400:
                raise RuntimeError(_format_dashscope_error(poll))
            body = poll.json()
            if not isinstance(body, dict):
                raise RuntimeError("生图任务查询格式异常")
            out = body.get("output") if isinstance(body.get("output"), dict) else {}
            status = str(out.get("task_status") or "").upper()
            if status == "SUCCEEDED":
                return body
            if status in {"FAILED", "CANCELED", "UNKNOWN"}:
                message = str(body.get("message") or out.get("message") or status)
                raise RuntimeError(f"生图任务失败：{message}")
            # PENDING / RUNNING 继续等
        raise RuntimeError("生图超时，请稍后重试")


def parse_image_generate_response(data: dict[str, Any], *, model: str) -> ImageGenerateResult:
    """解析同步或异步成功响应中的图片 URL。"""
    output = data.get("output")
    if not isinstance(output, dict):
        raise RuntimeError("生图结果缺少 output")

    images: list[GeneratedImage] = []
    choices = output.get("choices")
    if isinstance(choices, list):
        for choice in choices:
            if not isinstance(choice, dict):
                continue
            message = choice.get("message")
            if not isinstance(message, dict):
                continue
            content = message.get("content")
            if not isinstance(content, list):
                continue
            for item in content:
                if not isinstance(item, dict):
                    continue
                url = item.get("image")
                if isinstance(url, str) and url.strip():
                    images.append(GeneratedImage(url=url.strip()))

    # 旧版异步结果偶发 results[].url
    if not images:
        results = output.get("results")
        if isinstance(results, list):
            for item in results:
                if not isinstance(item, dict):
                    continue
                url = item.get("url") or item.get("image")
                if isinstance(url, str) and url.strip():
                    images.append(GeneratedImage(url=url.strip()))

    if not images:
        raise RuntimeError("生图成功但未返回图片地址")

    usage_raw = data.get("usage")
    usage = usage_raw if isinstance(usage_raw, dict) else None
    size = None
    if usage and isinstance(usage.get("size"), str):
        size = usage["size"]
    return ImageGenerateResult(images=images, model=model, size=size, usage=usage)


def _trace_request(payload: dict[str, Any]) -> dict[str, Any]:
    """trace 里保留提示词摘要与参考图数量，不落 base64。"""
    messages = (
        ((payload.get("input") or {}).get("messages") or [])
        if isinstance(payload.get("input"), dict)
        else []
    )
    prompt = ""
    ref_count = 0
    if messages and isinstance(messages[0], dict):
        content = messages[0].get("content")
        if isinstance(content, list):
            for item in content:
                if not isinstance(item, dict):
                    continue
                if isinstance(item.get("image"), str) and item["image"].strip():
                    ref_count += 1
                text = item.get("text")
                if isinstance(text, str) and text.strip():
                    prompt = text
    return {
        "model": payload.get("model"),
        "prompt": prompt[:500],
        "reference_image_count": ref_count,
        "parameters": payload.get("parameters"),
    }


def _requires_async(response: httpx.Response) -> bool:
    try:
        body = response.json()
    except Exception:
        return "synchronous" in (response.text or "").lower()
    if not isinstance(body, dict):
        return False
    return _message_requires_async(str(body.get("message") or ""))


def _message_requires_async(message: str) -> bool:
    lowered = message.lower()
    return "synchronous" in lowered or "does not support sync" in lowered


def _format_dashscope_error(response: httpx.Response) -> str:
    try:
        body = response.json()
    except Exception:
        return f"生图请求失败 HTTP {response.status_code}"
    if isinstance(body, dict):
        return _format_body_error(body)
    return f"生图请求失败 HTTP {response.status_code}"


def _format_body_error(body: dict[str, Any]) -> str:
    code = body.get("code")
    message = body.get("message")
    err = body.get("error")
    if isinstance(err, dict):
        code = code or err.get("code")
        message = message or err.get("message")
    parts = [p for p in (str(code) if code else None, str(message) if message else None) if p]
    return "生图失败：" + (" — ".join(parts) if parts else "未知错误")
