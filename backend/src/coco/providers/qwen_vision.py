"""阿里云百炼视觉模型（OpenAI 兼容 HTTP）：帮我看看识图。

图片仅以内存中的 base64 data URL 转发，不落盘；调用方负责在请求结束后丢弃原图。
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass
from typing import Any, Literal

import httpx
from pydantic import SecretStr

logger = logging.getLogger(__name__)

Confidence = Literal["high", "low"]

_LOOK_SYSTEM = """
你是 Coco，帮助老人看懂眼前的照片（包装、纸张、手机截图、按钮等）。
必须遵守：
1. 只根据图片可见内容作答，看不清就说看不清（confidence=low），不要猜测。
2. 不做医疗诊断，不解释药效，不建议剂量或停药；可读出药盒上的文字。
3. 不把未知链接、陌生通知判定为绝对安全。
4. 不写入记忆、不创建提醒、不联系家人；只解释眼前这张图。
5. 语气亲切、简短、口语化；headline 最多两行大字结论。
6. 只输出一个 JSON 对象，不要 markdown 代码块，不要解释。字段：
   - confidence: "high" 或 "low"
   - headline: 大字结论（看不清时用空字符串）
   - detail: 一句话说明
   - safety_note: 必要安全提示，没有则空字符串
""".strip()


@dataclass(slots=True)
class LookResult:
    confidence: Confidence
    headline: str
    detail: str
    safety_note: str


class QwenVisionClient:
    def __init__(
        self,
        *,
        api_key: SecretStr,
        model: str,
        base_url: str = "https://dashscope.aliyuncs.com/compatible-mode/v1",
        timeout_seconds: float = 45.0,
    ) -> None:
        self._api_key = api_key
        self.model = model
        self.base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds

    async def look(
        self,
        *,
        image_data_url: str,
        question: str | None = None,
    ) -> LookResult:
        """对一张图给出结构化识图结果。"""
        user_text = (question or "").strip() or "请帮我看看这张图里写了什么、是什么意思。"
        payload: dict[str, Any] = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": _LOOK_SYSTEM},
                {
                    "role": "user",
                    "content": [
                        {"type": "image_url", "image_url": {"url": image_data_url}},
                        {"type": "text", "text": user_text},
                    ],
                },
            ],
            "temperature": 0.2,
            # 短任务关闭思考，降低延迟与费用
            "enable_thinking": False,
            "response_format": {"type": "json_object"},
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
            raise RuntimeError("识图模型返回格式异常") from exc
        if not isinstance(content, str) or not content.strip():
            raise RuntimeError("识图模型返回空内容")
        return parse_look_content(content)


def parse_look_content(raw: str) -> LookResult:
    """解析模型 JSON；容错去掉偶发的代码围栏。"""
    text = raw.strip()
    fence = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if fence:
        text = fence.group(1).strip()
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RuntimeError("识图结果不是合法 JSON") from exc
    if not isinstance(data, dict):
        raise RuntimeError("识图结果格式异常")

    confidence_raw = str(data.get("confidence") or "low").strip().lower()
    confidence: Confidence = "high" if confidence_raw == "high" else "low"
    headline = str(data.get("headline") or "").strip()
    detail = str(data.get("detail") or "").strip()
    safety_note = str(data.get("safety_note") or "").strip()

    if confidence == "low":
        # 看不清时不展示可能误导的结论
        headline = ""
        if not detail:
            detail = "我看不太清这上面的字。"
    elif not headline and not detail:
        confidence = "low"
        detail = "我看不太清这上面的字。"

    return LookResult(
        confidence=confidence,
        headline=headline,
        detail=detail,
        safety_note=safety_note,
    )


def unclear_look_result() -> LookResult:
    """无 Key / 调用失败时的看不清兜底，不假装成功。"""
    return LookResult(
        confidence="low",
        headline="",
        detail="我现在看不太清。您可以重新拍一张，或请家人帮忙看。",
        safety_note="",
    )
