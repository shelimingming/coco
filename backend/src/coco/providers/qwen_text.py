"""阿里云百炼文本模型（OpenAI 兼容 HTTP）：子女报平安转译等无状态请求。"""

from __future__ import annotations

import logging
from dataclasses import dataclass

import httpx
from pydantic import SecretStr

logger = logging.getLogger(__name__)

_TRANSLATE_SYSTEM = """
你是 Coco，帮助子女把简短报平安消息转成老人更容易听懂的口语表达。
规则：
1. 保留事实，不夸大、不添医疗判断。
2. 语气亲切、简短，一两句话即可。
3. 若原文已清晰，可轻微润色后原样返回。
4. 只输出转译后的正文，不要解释、不加引号。
""".strip()


@dataclass(slots=True)
class TranslateResult:
    text: str
    translated: bool


class QwenTextClient:
    def __init__(
        self,
        *,
        api_key: SecretStr,
        model: str,
        base_url: str = "https://dashscope.aliyuncs.com/compatible-mode/v1",
        timeout_seconds: float = 20.0,
    ) -> None:
        self._api_key = api_key
        self.model = model
        self.base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds

    async def translate_child_status(
        self, text: str, *, child_name: str = "孩子"
    ) -> TranslateResult:
        """把子女原话转成老人易懂表达；失败时由调用方决定是否降级。"""
        user_prompt = f"子女称呼：{child_name}\n原文：{text.strip()}\n请转成老人容易理解的一句话。"
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": _TRANSLATE_SYSTEM},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": 0.4,
        }
        headers = {
            "Authorization": f"Bearer {self._api_key.get_secret_value()}",
            "Content-Type": "application/json",
        }
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(
                f"{self.base_url}/chat/completions",
                headers=headers,
                json=payload,
            )
            response.raise_for_status()
            data = response.json()
        try:
            content = data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise RuntimeError("文本模型返回格式异常") from exc
        if not isinstance(content, str) or not content.strip():
            raise RuntimeError("文本模型返回空内容")
        return TranslateResult(text=content.strip(), translated=True)


async def translate_or_passthrough(
    *,
    api_key: SecretStr | None,
    model: str,
    text: str,
    child_name: str = "孩子",
) -> TranslateResult:
    """无 Key 或调用失败时降级为原文透传，保证本地可跑通闭环。"""
    cleaned = text.strip()
    if not cleaned:
        return TranslateResult(text="", translated=False)
    if api_key is None or not api_key.get_secret_value().strip():
        return TranslateResult(text=cleaned, translated=False)
    try:
        client = QwenTextClient(api_key=api_key, model=model)
        return await client.translate_child_status(cleaned, child_name=child_name)
    except Exception:
        logger.warning("text_translate_failed", exc_info=True)
        return TranslateResult(text=cleaned, translated=False)
