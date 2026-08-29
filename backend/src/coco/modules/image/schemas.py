"""文生图请求 / 响应 DTO。"""

from __future__ import annotations

from pydantic import BaseModel, Field


class ImageGenerateRequest(BaseModel):
    prompt: str = Field(..., min_length=1, max_length=5000, description="正向提示词")
    negative_prompt: str | None = Field(
        default=None,
        max_length=500,
        description="反向提示词；wan2.6-t2i 等支持",
    )
    # wan2.7 用 1K/2K/4K；wan2.6-t2i 用 1280*1280 这类宽*高
    size: str | None = Field(default=None, max_length=32)
    n: int = Field(default=1, ge=1, le=4, description="生成张数，按张计费")
    watermark: bool = False
    seed: int | None = Field(default=None, ge=0, le=2147483647)
    # None 表示按模型默认（2.7 开思考；t2i 开改写）
    thinking_mode: bool | None = None
    prompt_extend: bool | None = None


class GeneratedImageItem(BaseModel):
    url: str


class ImageGenerateResponse(BaseModel):
    images: list[GeneratedImageItem]
    model: str
    size: str | None = None
    # 提醒调用方：百炼临时链约 24h，需自行下载保存
    expires_hint: str = "图片链接约 24 小时内有效，请及时保存"
