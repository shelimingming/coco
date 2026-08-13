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
你是 Coco，帮助老人看懂眼前的照片（包装、纸张、手机截图、实物、按钮等）。
你的输出会交给语音陪伴模型当上下文，不是直接念给老人听的短结论。
必须遵守：
1. 只根据图片可见内容描述，看不清就写清「看不清」之处（confidence=low），不要猜测。
2. 不做医疗诊断，不解释药效，不建议剂量或停药；可读出药盒上的文字。
3. 不把未知链接、陌生通知判定为绝对安全。
4. 不写入记忆、不创建提醒、不联系家人；只描述眼前这张图。
5. 只输出一个 JSON 对象，不要 markdown 代码块，不要解释。字段：
   - confidence: "high" 或 "low"
   - scene_description: 详细场景描述（人物/物体/布局/颜色/图上文字 OCR；
     看不清的部分明确写出；约 80～300 字，供语音模型转述）
   - headline: 一两句大字结论（看不清时用空字符串）
   - detail: 一句话补充说明
   - safety_note: 必要安全提示，没有则空字符串
""".strip()

_FOLLOW_UP_SYSTEM = """
你是 Coco，正在根据同一张照片继续回答老人的追问。
必须遵守：
1. 结合图片与已有对话回答；看不清就诚实说看不清，不要编造。
2. 不做医疗诊断，不建议剂量或停药；可读出图上的文字。
3. 不把未知链接判定为绝对安全。
4. 不要写入记忆、创建提醒或联系家人；本轮只口头解释。
5. 语气亲切、简短、口语化，一两句话即可，适合直接朗读。
6. 只输出回答正文，不要引号、不要 markdown、不要解释规则。
""".strip()


@dataclass(slots=True)
class LookResult:
    confidence: Confidence
    headline: str
    detail: str
    safety_note: str
    # 给 Realtime 语音注入用的详细读图文本
    scene_description: str = ""


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

    async def follow_up(
        self,
        *,
        image_data_url: str,
        history: list[tuple[str, str]],
        user_text: str,
    ) -> str:
        """同图多轮追问；history 为 (role, text)，role 仅 user/assistant。"""
        cleaned = user_text.strip()
        if not cleaned:
            raise RuntimeError("没有听到问题")

        messages: list[dict[str, Any]] = [
            {"role": "system", "content": _FOLLOW_UP_SYSTEM},
        ]
        # 首轮用户消息带图，后续历史纯文本
        first_user_done = False
        for role, text in history:
            piece = text.strip()
            if not piece or role not in {"user", "assistant"}:
                continue
            if role == "user" and not first_user_done:
                messages.append(
                    {
                        "role": "user",
                        "content": [
                            {"type": "image_url", "image_url": {"url": image_data_url}},
                            {"type": "text", "text": piece},
                        ],
                    }
                )
                first_user_done = True
            else:
                messages.append({"role": role, "content": piece})

        if not first_user_done:
            messages.append(
                {
                    "role": "user",
                    "content": [
                        {"type": "image_url", "image_url": {"url": image_data_url}},
                        {"type": "text", "text": cleaned},
                    ],
                }
            )
        else:
            messages.append({"role": "user", "content": cleaned})

        payload: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.4,
            "enable_thinking": False,
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
            raise RuntimeError("追问模型返回格式异常") from exc
        if not isinstance(content, str) or not content.strip():
            raise RuntimeError("追问模型返回空内容")
        return content.strip()


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
    scene_description = str(data.get("scene_description") or "").strip()

    if confidence == "low":
        # 看不清时不展示可能误导的结论
        headline = ""
        if not detail:
            detail = "我看不太清这上面的字。"
    elif not headline and not detail and not scene_description:
        confidence = "low"
        detail = "我看不太清这上面的字。"

    # 模型偶发漏写 scene_description：用 headline+detail 兜底，保证可注入语音
    if not scene_description:
        parts = [p for p in (headline, detail, safety_note) if p]
        scene_description = " ".join(parts) if parts else "我看不太清这上面的字。"

    return LookResult(
        confidence=confidence,
        headline=headline,
        detail=detail,
        safety_note=safety_note,
        scene_description=scene_description,
    )


def unclear_look_result() -> LookResult:
    """无 Key / 调用失败时的看不清兜底，不假装成功。"""
    unclear = "我现在看不太清。您可以重新拍一张，或请家人帮忙看。"
    return LookResult(
        confidence="low",
        headline="",
        detail=unclear,
        safety_note="",
        scene_description=unclear,
    )
