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
    PURPOSE_TEXT_DAILY_NOTE_EXTRACT,
    PURPOSE_TEXT_DAILY_NOTE_WRITE,
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

_DAILY_NOTE_EXTRACT_SYSTEM = """
你是对话整理助手。下面是一位老人与AI助手「可可」今天全天的对话记录，请提取真实信息，输出JSON。
规则：
1. 只提取对话中明确出现的内容，禁止推测、禁止编造。
2. 老人没有明确表达的情绪不要猜；拿不准的信息标记 "uncertain": true。
3. 原话摘录：保留1-3句最有生活气息的原话（口头禅、方言、具体细节）。
4. 健康与情绪信号只做客观记录，不下任何结论；没有则为空数组。
5. image_concepts：仅根据对话里明确提到的真实活动/地点写 0～3 个画面（各一句话）；
   对话没出现的场景一律不要写；没有可画场景则 []。
6. weather_mentioned：对话里若明确提到天气/晴雨冷暖则填写短词，否则空字符串。
输出格式（只输出 JSON，不要其它文字）：
{
  "topics": [],
  "events": [],
  "people": [],
  "mood": {"emotion": "", "evidence": "", "uncertain": false},
  "quotes": [],
  "health_signals": [],
  "image_concepts": [],
  "weather_mentioned": ""
}
""".strip()

_DAILY_NOTE_WRITE_SYSTEM = """
你是「可可」，一只金毛小狗，也是老人身边暖暖的陪伴。
每晚你根据白天聊天，用自己的视角写一篇短日记，留给老人和家人看。
写作规则：
1. 视角：以可可「我」来写——陪在人身边听、看、记；
   称呼对方用「您」或已知称呼，不要写成老人本人的日记。
2. 严禁捏造：事、人、地点、活动必须来自「已知信息」；
   对话没说的（如买菜、广场舞、喝豆浆、街边摊等）一律不许写进正文。
3. 可润色：可改语气、加陪伴感与轻感悟，可化用 quotes；但不能用润色当借口补情节。
4. 不要流水账：禁止「然后…最后…」式罗列；用 2～4 段把已知小事写得连贯、有温度。
5. 感悟：一两句轻柔心里话即可，不煽情、不说教。
6. 语气：口语、短句、温暖；不要连用感叹号。
7. 篇幅：120-250字；素材少就写短，不硬凑。
8. 标题：5-10字，概括已知事实里最暖的一点；禁止「你好呀」「今天」「日记」。
9. 开头避免天天用「今天」；收尾一句轻轻收束，不要连环提问。
10. 禁止：医学判断、家庭矛盾细节、health_signals、说教、「虽然您年纪大了」。
11. 最近几天的日记仅供避免重复：换句式，不要照抄，更不要借机编新事。
12. illustrations：与正文段落一一对应（条数=正文段数，最多3条）；
    每条一句话描述该段配图，必须只画该段已写到的内容，禁止加段外情节。
输出格式（只输出 JSON，不要其它文字）：
{
  "title": "小标题，5-10字",
  "body": "正文（用\\n分段）",
  "closing": "一句话收尾",
  "illustrations": ["与第1段对应的画面", "与第2段对应的画面"]
}
""".strip()

_TITLE_MAX_LEN = 16
_FALLBACK_TITLE_MAX = 24
_WEB_SEARCH_UNAVAILABLE = "暂时查不了网上的消息，您可以过会儿再问。"
_DAILY_NOTE_EMPTY_GUIDANCE = "今天聊得还不多，再和可可说说今天发生了什么，我再帮您写日记。"
_WEEKDAY_CN = ("星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日")


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

    async def extract_daily_note(self, transcript: str) -> dict:
        """从当日转写提取结构化事实（防编造）。"""
        content = await self._chat(
            system=_DAILY_NOTE_EXTRACT_SYSTEM,
            user=f"对话记录：\n{transcript.strip()}",
            temperature=0.2,
            purpose=PURPOSE_TEXT_DAILY_NOTE_EXTRACT,
        )
        return parse_daily_note_extraction_json(content)

    async def write_daily_note_diary(
        self,
        *,
        extraction: dict,
        recent_diaries: list[str],
        display_name: str,
    ) -> dict:
        """根据提取结果以可可视角撰写日记。"""
        name = (display_name or "").strip() or "老人"
        recent_block = "\n---\n".join(recent_diaries) if recent_diaries else "（暂无）"
        import json

        user = (
            f"对方称呼：{name}\n"
            f"已知信息：\n{json.dumps(extraction, ensure_ascii=False)}\n\n"
            f"最近几天的日记（仅供避免重复，不要照抄）：\n{recent_block}"
        )
        content = await self._chat(
            system=_DAILY_NOTE_WRITE_SYSTEM,
            user=user,
            temperature=0.45,
            purpose=PURPOSE_TEXT_DAILY_NOTE_WRITE,
        )
        return parse_daily_note_diary_json(content)


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
    """兼容旧解析：从 {"items":[...]} 取短句；失败返回空列表。"""
    import json

    text = _strip_json_fence(raw)
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


def _strip_json_fence(raw: str) -> str:
    text = raw.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    return text.strip()


def _str_list(value: object, *, limit: int = 8, max_len: int = 120) -> list[str]:
    if not isinstance(value, list):
        return []
    out: list[str] = []
    for item in value:
        if isinstance(item, str) and item.strip():
            out.append(item.strip()[:max_len])
        if len(out) >= limit:
            break
    return out


def empty_daily_note_extraction() -> dict:
    return {
        "topics": [],
        "events": [],
        "people": [],
        "mood": {"emotion": "", "evidence": "", "uncertain": True},
        "quotes": [],
        "health_signals": [],
        "image_concepts": [],
        "weather_mentioned": "",
    }


def parse_daily_note_extraction_json(raw: str) -> dict:
    """解析提取 JSON；失败返回空结构。"""
    import json

    text = _strip_json_fence(raw)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return empty_daily_note_extraction()
    if not isinstance(data, dict):
        return empty_daily_note_extraction()
    mood_raw = data.get("mood") if isinstance(data.get("mood"), dict) else {}
    weather = data.get("weather_mentioned")
    return {
        "topics": _str_list(data.get("topics"), limit=6),
        "events": _str_list(data.get("events"), limit=6),
        "people": _str_list(data.get("people"), limit=6),
        "mood": {
            "emotion": str(mood_raw.get("emotion") or "").strip()[:40],
            "evidence": str(mood_raw.get("evidence") or "").strip()[:120],
            "uncertain": bool(mood_raw.get("uncertain", False)),
        },
        "quotes": _str_list(data.get("quotes"), limit=3, max_len=80),
        "health_signals": _str_list(data.get("health_signals"), limit=4),
        "image_concepts": _str_list(data.get("image_concepts"), limit=4, max_len=100),
        "weather_mentioned": str(weather or "").strip()[:20] if isinstance(weather, str) else "",
    }


def parse_daily_note_diary_json(raw: str) -> dict:
    """解析撰写 JSON → title/body/closing/illustrations；失败返回空。"""
    import json

    text = _strip_json_fence(raw)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return {"title": "", "body": "", "closing": "", "illustrations": []}
    if not isinstance(data, dict):
        return {"title": "", "body": "", "closing": "", "illustrations": []}
    title = str(data.get("title") or "").strip()[:24]
    body = str(data.get("body") or "").strip()[:800]
    closing = str(data.get("closing") or "").strip()[:120]
    illustrations = _str_list(data.get("illustrations"), limit=3, max_len=100)
    return {
        "title": title,
        "body": body,
        "closing": closing,
        "illustrations": illustrations,
    }


def fallback_daily_note_extraction(transcript: str) -> dict:
    """无 Key 时从用户话抽事实，填入提取结构。"""
    base = empty_daily_note_extraction()
    quotes: list[str] = []
    for raw in transcript.splitlines():
        line = raw.strip()
        if line.startswith("用户：") or line.startswith("老人："):
            body = line.split("：", 1)[-1].strip()
            if len(body) >= 4:
                quotes.append(body[:80])
        if len(quotes) >= 3:
            break
    base["quotes"] = quotes
    base["events"] = list(quotes)
    base["topics"] = [q[:20] for q in quotes[:3]]
    base["image_concepts"] = [f"与「{q[:24]}」相关的日常画面" for q in quotes[:3]]
    return base


def fallback_daily_note_items(transcript: str) -> list[str]:
    """兼容旧接口：无 Key 时从用户话里抽短句。"""
    return fallback_daily_note_extraction(transcript)["quotes"]


def extraction_has_diary_material(extraction: dict) -> bool:
    """是否有足够素材写日记（事件/原话/话题任一实质非空）。"""
    for key in ("events", "quotes", "topics"):
        values = extraction.get(key)
        if isinstance(values, list) and any(isinstance(x, str) and x.strip() for x in values):
            return True
    return False


def build_daily_note_header_line(
    note_date,
    *,
    weather_mentioned: str = "",
) -> str:
    """首行：月日 + 星期 + 可选天气（仅对话提到时）。"""
    from datetime import date as date_cls

    if not isinstance(note_date, date_cls):
        return ""
    weekday = _WEEKDAY_CN[note_date.weekday()]
    header = f"{note_date.month}月{note_date.day}日 {weekday}"
    weather = (weather_mentioned or "").strip()
    if weather:
        header = f"{header} {weather}"
    return header


def diary_paragraphs(body: str) -> list[str]:
    """正文按空行/换行拆段，过滤空段。"""
    if not body.strip():
        return []
    parts = re.split(r"\n+", body.strip())
    return [p.strip() for p in parts if p.strip()][:6]


def fallback_diary_from_extraction(extraction: dict) -> dict:
    """模型撰写失败时：可可视角短文，只串联已知事实，不编造。"""
    quotes = _str_list(extraction.get("quotes"), limit=3)
    events = _str_list(extraction.get("events"), limit=3)
    people = _str_list(extraction.get("people"), limit=2)
    bits = events or quotes
    if not bits:
        return {"title": "", "body": "", "closing": "", "illustrations": []}
    who = people[0] if people else "您"
    seed = bits[0].rstrip("。！？，,")
    title = (seed[:10] if len(seed) >= 4 else "今天这点事").rstrip("。！？")
    mid = "，还".join(bits[:2]) if len(bits) > 1 else bits[0]
    if not mid.endswith(("。", "！", "？")):
        mid = f"{mid}。"
    para1 = f"今天听{who}说起这些，我都记在心里了。"
    para2 = mid
    para3 = "能陪在旁边听听这些小事，我就觉得挺踏实。"
    body = f"{para1}\n{para2}\n{para3}"
    # 配图只跟已写段落走，画面描述不另造情节
    illustrations = [
        f"可可趴在一旁听{who}说话",
        f"与「{seed[:24]}」相关的温馨陪伴画面",
    ][: min(2, len(bits) + 1)]
    return {
        "title": title[:24] or "今天这点事",
        "body": body[:800],
        "closing": "我在这儿陪着，明天再聊。",
        "illustrations": illustrations,
    }


def verify_diary_against_sources(
    *,
    diary: dict,
    extraction: dict,
    transcript: str,
) -> bool:
    """轻校验：允许润色；只拦「完全对不上已知事实」的空编。"""
    body = f"{diary.get('title', '')}\n{diary.get('body', '')}\n{diary.get('closing', '')}"
    if len(body.strip()) < 20:
        return False
    # 收集事实锚点：事件/原话/话题里截短词
    anchors: list[str] = []
    for key in ("events", "quotes", "topics", "people"):
        for item in extraction.get(key) or []:
            if not isinstance(item, str):
                continue
            cleaned = re.sub(r"[\s，,。！？、]+", "", item.strip())
            if len(cleaned) >= 2:
                anchors.append(cleaned[:4])
            if len(cleaned) >= 6:
                anchors.append(cleaned[2:6])
    if not anchors:
        # 无锚点时只要求有正文（素材门禁应已挡住空素材）
        return True
    # 润色后不必逐字复现；命中任一锚点即可
    return any(a and a in body for a in anchors)


def daily_note_empty_guidance() -> str:
    return _DAILY_NOTE_EMPTY_GUIDANCE


async def extract_daily_note_or_fallback(
    *,
    api_key: SecretStr | None,
    model: str,
    transcript: str,
    base_url: str = "https://dashscope.aliyuncs.com/compatible-mode/v1",
    timeout_seconds: float = 30.0,
) -> dict:
    cleaned = transcript.strip()
    if not cleaned:
        return empty_daily_note_extraction()
    if api_key is None or not api_key.get_secret_value().strip():
        await record_llm_trace(
            purpose=PURPOSE_TEXT_DAILY_NOTE_EXTRACT,
            modality="text",
            model=model,
            status="skipped",
            request_json={"transcript": cleaned[:2000]},
            error_message="未配置 API Key，使用转写兜底提取",
        )
        return fallback_daily_note_extraction(cleaned)
    try:
        client = QwenTextClient(
            api_key=api_key,
            model=model,
            base_url=base_url,
            timeout_seconds=timeout_seconds,
        )
        return await client.extract_daily_note(cleaned)
    except Exception:
        logger.warning("daily_note_extract_failed", exc_info=True)
        return fallback_daily_note_extraction(cleaned)


async def write_daily_note_or_fallback(
    *,
    api_key: SecretStr | None,
    model: str,
    extraction: dict,
    recent_diaries: list[str],
    display_name: str,
    transcript: str,
    base_url: str = "https://dashscope.aliyuncs.com/compatible-mode/v1",
    timeout_seconds: float = 45.0,
) -> dict:
    """撰写日记；失败或校验不过则用提取结果拼短文。"""
    fallback = fallback_diary_from_extraction(extraction)
    if api_key is None or not api_key.get_secret_value().strip():
        await record_llm_trace(
            purpose=PURPOSE_TEXT_DAILY_NOTE_WRITE,
            modality="text",
            model=model,
            status="skipped",
            request_json={"extraction": extraction},
            error_message="未配置 API Key，使用提取拼短文",
        )
        return fallback
    try:
        client = QwenTextClient(
            api_key=api_key,
            model=model,
            base_url=base_url,
            timeout_seconds=timeout_seconds,
        )
        diary = await client.write_daily_note_diary(
            extraction=extraction,
            recent_diaries=recent_diaries,
            display_name=display_name,
        )
        if not (diary.get("body") or "").strip():
            return fallback
        if not verify_diary_against_sources(
            diary=diary, extraction=extraction, transcript=transcript
        ):
            logger.info("daily_note_verify_failed_using_fallback")
            return fallback
        return diary
    except Exception:
        logger.warning("daily_note_write_failed", exc_info=True)
        return fallback


async def daily_note_items_or_fallback(
    *,
    api_key: SecretStr | None,
    model: str,
    transcript: str,
    base_url: str = "https://dashscope.aliyuncs.com/compatible-mode/v1",
    timeout_seconds: float = 30.0,
) -> list[str]:
    """兼容旧调用：返回 quotes/events 短句列表。"""
    extraction = await extract_daily_note_or_fallback(
        api_key=api_key,
        model=model,
        transcript=transcript,
        base_url=base_url,
        timeout_seconds=timeout_seconds,
    )
    quotes = extraction.get("quotes") or []
    events = extraction.get("events") or []
    items = [x for x in quotes if isinstance(x, str) and x.strip()]
    if not items:
        items = [x for x in events if isinstance(x, str) and x.strip()]
    return items[:3]


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
