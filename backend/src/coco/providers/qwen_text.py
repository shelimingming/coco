"""阿里云百炼文本模型（OpenAI 兼容 HTTP）：转译、会话标题等无状态请求。"""

from __future__ import annotations

import logging
import re
import time
from dataclasses import dataclass
from datetime import UTC, datetime

import httpx
from pydantic import SecretStr

from coco.observability.llm_trace import (
    PURPOSE_TEXT_DAILY_NOTE,
    PURPOSE_TEXT_TITLE,
    PURPOSE_TEXT_TRANSLATE,
    PURPOSE_TEXT_WEB_SEARCH,
    record_llm_trace,
    usage_from_openai,
)

logger = logging.getLogger(__name__)

_TRANSLATE_SYSTEM = """
你是可可，用自己的旁白把子女的报平安转成老人更容易听懂的口语。
规则：
1. 必须第三人称：主语用用户给出的「子女称呼」（如小林），例如「小林已经吃过饭了，让您放心」。
2. 禁止对老人喊「妈/爸/妈妈/爸爸」等称呼；禁止用子女第一人称「我…」代替孩子说话。
3. 保留事实，不夸大、不添医疗判断；语气亲切、简短，一两句话即可。
4. 若原文已清晰，可轻微润色，但仍须第三人称。
5. 只输出转译后的正文，不要解释、不加引号。
正例：原文「吃过饭了」→「小林已经吃过饭了，让您放心」。
""".strip()

_TITLE_SYSTEM = """
你是 Coco，为老人与可可的一次语音聊天生成短标题，方便在历史记录里辨认。
规则：
1. 用简短中文，尽量不超过 12 个字，最多 16 个字。
2. 概括这次聊天在聊什么，不要整句复述原话。
3. 语气亲切自然；不做医疗判断，不夸大。
4. 只输出标题本身，不要引号、标点装饰或解释。
""".strip()

# 语音 web_search：联网后整理成可口述的短答，供 Realtime 播报
_WEB_SEARCH_SYSTEM = """
你是可可的联网助手，根据实时检索结果回答老人的问题。
规则：
1. 只用中文，口语化，2～4 句，方便别人朗读；不要列表、不要长链接、不要角标。
2. 优先给事实：天气说冷暖与是否下雨；新闻说一两件大事即可。
3. 若检索不到或不确定，诚实说「暂时没查到」或「信息不够准」，不要编造。
4. 禁止医疗诊断、药量/处方建议、投资买卖建议、虚假救援承诺。
5. 只输出可直接口述的正文，不要解释「我搜索了」或加标题。
""".strip()

_DAILY_NOTE_SYSTEM = """
你是可可，根据老人当天与你的真实交流，整理「每日小记」条目。
规则：
1. 只输出 JSON 对象：{"items":["……","……"]}，不要其它文字。
2. items 选 1～3 条有意义的日常生活事实（吃饭、出门、和邻居聊天、心情等）。
3. 每条一句短中文，陈述事实，不要推断、诊断、敏感隐私、第三方隐私。
4. 不要写入需要子女紧急关注的身体异常（那些走「需要关注」通道）。
5. 交流里没有可分享日常时，返回 {"items":[]}。
""".strip()

_TITLE_MAX_LEN = 16
_FALLBACK_TITLE_MAX = 24
_WEB_SEARCH_UNAVAILABLE = "暂时查不了网上的消息，您可以过会儿再问。"

# 模型偶发冒充子女：句首喊爸妈，或用「我…」开场
_PARENT_ADDRESS_RE = re.compile(r"^(妈|爸|妈妈|爸爸|爹|娘|母亲|父亲)[，,！!、]")
_CHILD_FIRST_PERSON_RE = re.compile(r"^我(刚|已经|在|吃|到|准备|忙|还|先|马上|现在|来)")


@dataclass(slots=True)
class TranslateResult:
    text: str
    translated: bool


@dataclass(slots=True)
class TitleResult:
    title: str
    generated: bool


@dataclass(slots=True)
class WebSearchResult:
    """语音联网工具结果；status=ok 时 answer 可口述。"""

    status: str
    query: str
    answer: str = ""
    message: str = ""


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
        purpose: str,
        extra_body: dict[str, object] | None = None,
    ) -> str:
        payload: dict[str, object] = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temperature,
        }
        # 百炼非 OpenAI 标准字段（如 enable_search）平铺进 JSON
        if extra_body:
            payload.update(extra_body)
        headers = {
            "Authorization": f"Bearer {self._api_key.get_secret_value()}",
            "Content-Type": "application/json",
        }
        started = datetime.now(UTC)
        t0 = time.perf_counter()
        try:
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
            text = content.strip()
            # 联网请求体可能含长检索痕迹，落库只保留问句与摘要，避免日志膨胀
            request_for_trace: dict[str, object] = {
                "model": self.model,
                "purpose": purpose,
                "user": user,
                "enable_search": bool(extra_body and extra_body.get("enable_search")),
            }
            await record_llm_trace(
                purpose=purpose,
                modality="text",
                model=self.model,
                status="ok",
                latency_ms=int((time.perf_counter() - t0) * 1000),
                request_json=request_for_trace if extra_body else payload,
                response_json={"content": text},
                usage_json=usage_from_openai(data),
                started_at=started,
            )
            return text
        except Exception as exc:
            await record_llm_trace(
                purpose=purpose,
                modality="text",
                model=self.model,
                status="error",
                latency_ms=int((time.perf_counter() - t0) * 1000),
                request_json=payload if not extra_body else {"model": self.model, "user": user},
                error_message=str(exc),
                started_at=started,
            )
            raise

    async def translate_child_status(
        self, text: str, *, child_name: str = "孩子"
    ) -> TranslateResult:
        """把子女原话转成老人易懂的第三人称旁白；失败时由调用方决定是否降级。"""
        original = text.strip()
        name = (child_name or "").strip() or "孩子"
        user_prompt = (
            f"子女称呼：{name}\n原文：{original}\n"
            "请用第三人称转述成老人容易理解的一句话，主语必须用上面的子女称呼。"
        )
        content = await self._chat(
            system=_TRANSLATE_SYSTEM,
            user=user_prompt,
            temperature=0.4,
            purpose=PURPOSE_TEXT_TRANSLATE,
        )
        # 模型偶发第一人称时回退，避免预览出现「妈，我…」
        safe = sanitize_child_status_relay(content, original=original, child_name=name)
        return TranslateResult(text=safe, translated=True)

    async def generate_conversation_title(self, transcript: str) -> TitleResult:
        """根据对话摘录生成短标题；失败时由调用方降级。"""
        user_prompt = f"下面是一次聊天的摘录，请生成一个短标题：\n{transcript.strip()}"
        content = await self._chat(
            system=_TITLE_SYSTEM,
            user=user_prompt,
            temperature=0.3,
            purpose=PURPOSE_TEXT_TITLE,
        )
        return TitleResult(title=sanitize_conversation_title(content), generated=True)

    async def search_and_summarize(self, query: str) -> WebSearchResult:
        """强制联网检索并用口语摘要；供语音 web_search 工具调用。"""
        cleaned = query.strip()
        if not cleaned:
            return WebSearchResult(
                status="error",
                query="",
                message="没有听清要查什么，您可以再说一次。",
            )
        content = await self._chat(
            system=_WEB_SEARCH_SYSTEM,
            user=f"请根据联网检索结果回答：{cleaned}",
            temperature=0.3,
            purpose=PURPOSE_TEXT_WEB_SEARCH,
            extra_body={
                "enable_search": True,
                "search_options": {
                    "forced_search": True,
                    "search_strategy": "turbo",
                },
            },
        )
        return WebSearchResult(status="ok", query=cleaned, answer=content)

    async def extract_daily_note_items(self, transcript: str) -> list[str]:
        """从当日转写提炼 0～3 条日常事实。"""
        content = await self._chat(
            system=_DAILY_NOTE_SYSTEM,
            user=f"当天交流记录：\n{transcript.strip()}",
            temperature=0.2,
            purpose=PURPOSE_TEXT_DAILY_NOTE,
        )
        return parse_daily_note_items_json(content)


def looks_like_child_first_person(text: str) -> bool:
    """是否像子女第一人称或直接喊爸妈（不符合可可旁白）。"""
    cleaned = text.strip()
    if not cleaned:
        return False
    return bool(_PARENT_ADDRESS_RE.match(cleaned) or _CHILD_FIRST_PERSON_RE.match(cleaned))


def fallback_third_person_relay(original: str, *, child_name: str = "孩子") -> str:
    """违规输出时的确定性第三人称回退。"""
    name = (child_name or "").strip() or "孩子"
    body = original.strip()
    if not body:
        return f"{name}传来消息，让您放心。"
    return f"{name}说，{body}"


def sanitize_child_status_relay(model_text: str, *, original: str, child_name: str = "孩子") -> str:
    """合规则保留模型文案；命中第一人称/喊爸妈则回退。"""
    cleaned = model_text.strip().strip("「」『』“”\"'‘’")
    if looks_like_child_first_person(cleaned):
        return fallback_third_person_relay(original, child_name=child_name)
    return cleaned or fallback_third_person_relay(original, child_name=child_name)


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


def parse_daily_note_items_json(raw: str) -> list[str]:
    """解析模型返回的 items JSON；失败返回空列表。"""
    import json

    text = raw.strip()
    # 去掉偶发 markdown 围栏
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return []
    if not isinstance(data, dict):
        return []
    items = data.get("items")
    if not isinstance(items, list):
        return []
    cleaned: list[str] = []
    for item in items:
        if isinstance(item, str) and item.strip():
            cleaned.append(item.strip()[:80])
        if len(cleaned) >= 3:
            break
    return cleaned


def fallback_daily_note_items(transcript: str) -> list[str]:
    """无 Key 时从用户话里抽短句，最多 3 条。"""
    lines: list[str] = []
    for raw in transcript.splitlines():
        line = raw.strip()
        if line.startswith("用户：") or line.startswith("老人："):
            body = line.split("：", 1)[-1].strip()
            if len(body) >= 4:
                lines.append(body[:80])
        if len(lines) >= 3:
            break
    return lines


async def daily_note_items_or_fallback(
    *,
    api_key: SecretStr | None,
    model: str,
    transcript: str,
    base_url: str = "https://dashscope.aliyuncs.com/compatible-mode/v1",
    timeout_seconds: float = 30.0,
) -> list[str]:
    cleaned = transcript.strip()
    if not cleaned:
        return []
    if api_key is None or not api_key.get_secret_value().strip():
        await record_llm_trace(
            purpose=PURPOSE_TEXT_DAILY_NOTE,
            modality="text",
            model=model,
            status="skipped",
            request_json={"transcript": cleaned[:2000]},
            error_message="未配置 API Key，使用转写兜底",
        )
        return fallback_daily_note_items(cleaned)
    try:
        client = QwenTextClient(
            api_key=api_key,
            model=model,
            base_url=base_url,
            timeout_seconds=timeout_seconds,
        )
        return await client.extract_daily_note_items(cleaned)
    except Exception:
        logger.warning("daily_note_extract_failed", exc_info=True)
        return fallback_daily_note_items(cleaned)


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
        await record_llm_trace(
            purpose=PURPOSE_TEXT_TRANSLATE,
            modality="text",
            model=model,
            status="skipped",
            request_json={"text": cleaned, "child_name": child_name},
            error_message="未配置 API Key，原文透传",
        )
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
        await record_llm_trace(
            purpose=PURPOSE_TEXT_TITLE,
            modality="text",
            model=model,
            status="skipped",
            request_json={"transcript": cleaned, "preview": preview},
            response_json={"title": fallback},
            error_message="未配置 API Key，使用预览文案兜底",
        )
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


async def search_or_unavailable(
    *,
    api_key: SecretStr | None,
    model: str,
    query: str,
    enabled: bool = True,
    base_url: str = "https://dashscope.aliyuncs.com/compatible-mode/v1",
    timeout_seconds: float = 30.0,
) -> WebSearchResult:
    """语音联网搜索；开关关闭、无 Key 或调用失败时返回可口述的降级文案。"""
    cleaned = query.strip()
    if not cleaned:
        return WebSearchResult(
            status="error",
            query="",
            message="没有听清要查什么，您可以再说一次。",
        )
    if not enabled or api_key is None or not api_key.get_secret_value().strip():
        await record_llm_trace(
            purpose=PURPOSE_TEXT_WEB_SEARCH,
            modality="text",
            model=model,
            status="skipped",
            request_json={"query": cleaned},
            error_message="联网搜索未启用或未配置 API Key",
        )
        return WebSearchResult(
            status="error",
            query=cleaned,
            message=_WEB_SEARCH_UNAVAILABLE,
        )
    try:
        client = QwenTextClient(
            api_key=api_key,
            model=model,
            base_url=base_url,
            timeout_seconds=timeout_seconds,
        )
        return await client.search_and_summarize(cleaned)
    except Exception:
        logger.warning("web_search_failed", exc_info=True)
        return WebSearchResult(
            status="error",
            query=cleaned,
            message=_WEB_SEARCH_UNAVAILABLE,
        )
