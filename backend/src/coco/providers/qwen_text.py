"""阿里云百炼文本模型（OpenAI 兼容 HTTP）：转译、会话标题等无状态请求。"""

from __future__ import annotations

import logging
import re
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

_TITLE_SYSTEM = """
你是 Coco，为老人与可可的一次语音聊天生成短标题，方便在历史记录里辨认。
规则：
1. 用简短中文，尽量不超过 12 个字，最多 16 个字。
2. 概括这次聊天在聊什么，不要整句复述原话。
3. 语气亲切自然；不做医疗判断，不夸大。
4. 只输出标题本身，不要引号、标点装饰或解释。
""".strip()

_TITLE_MAX_LEN = 16
_FALLBACK_TITLE_MAX = 24


@dataclass(slots=True)
class TranslateResult:
    text: str
    translated: bool


@dataclass(slots=True)
class TitleResult:
    title: str
    generated: bool


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

    async def _chat(
        self,
        *,
        system: str,
        user: str,
        temperature: float,
    ) -> str:
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temperature,
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
        return content.strip()

    async def translate_child_status(
        self, text: str, *, child_name: str = "孩子"
    ) -> TranslateResult:
        """把子女原话转成老人易懂表达；失败时由调用方决定是否降级。"""
        user_prompt = f"子女称呼：{child_name}\n原文：{text.strip()}\n请转成老人容易理解的一句话。"
        content = await self._chat(
            system=_TRANSLATE_SYSTEM,
            user=user_prompt,
            temperature=0.4,
        )
        return TranslateResult(text=content, translated=True)

    async def generate_conversation_title(self, transcript: str) -> TitleResult:
        """根据对话摘录生成短标题；失败时由调用方降级。"""
        user_prompt = f"下面是一次聊天的摘录，请生成一个短标题：\n{transcript.strip()}"
        content = await self._chat(
            system=_TITLE_SYSTEM,
            user=user_prompt,
            temperature=0.3,
        )
        return TitleResult(title=sanitize_conversation_title(content), generated=True)


def sanitize_conversation_title(raw: str) -> str:
    """去掉模型偶发的引号/前缀，并截断到展示长度。"""
    text = raw.strip()
    text = text.strip("「」『』“”\"'‘’")
    # 去掉「标题：」这类前缀
    text = re.sub(r"^(标题|题目)[:：]\s*", "", text)
    text = text.splitlines()[0].strip() if text else ""
    if len(text) > _TITLE_MAX_LEN:
        text = text[:_TITLE_MAX_LEN]
    return text


def fallback_conversation_title(preview: str) -> str:
    """无 Key / 模型失败时用预览文案截断作标题。"""
    cleaned = preview.strip()
    if not cleaned or cleaned == "这次还没有记下说话内容":
        return "还没说上话"
    if len(cleaned) > _FALLBACK_TITLE_MAX:
        return cleaned[:_FALLBACK_TITLE_MAX] + "…"
    return cleaned


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


async def title_or_fallback(
    *,
    api_key: SecretStr | None,
    model: str,
    transcript: str,
    preview: str,
    timeout_seconds: float = 8.0,
) -> TitleResult:
    """结束通话时生成标题；无 Key 或失败时用预览文案兜底。"""
    fallback = fallback_conversation_title(preview)
    cleaned = transcript.strip()
    if not cleaned:
        return TitleResult(title=fallback, generated=False)
    if api_key is None or not api_key.get_secret_value().strip():
        return TitleResult(title=fallback, generated=False)
    try:
        client = QwenTextClient(
            api_key=api_key,
            model=model,
            timeout_seconds=timeout_seconds,
        )
        result = await client.generate_conversation_title(cleaned)
        if not result.title:
            return TitleResult(title=fallback, generated=False)
        return result
    except Exception:
        logger.warning("conversation_title_failed", exc_info=True)
        return TitleResult(title=fallback, generated=False)
