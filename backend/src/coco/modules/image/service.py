"""文生图业务：鉴权用户调用万相适配层；图片不落库。"""

from __future__ import annotations

import logging

from coco.config import Settings
from coco.errors import AppError
from coco.models.user import User
from coco.modules.image.schemas import (
    GeneratedImageItem,
    ImageGenerateRequest,
    ImageGenerateResponse,
)
from coco.observability.llm_trace import (
    PURPOSE_IMAGE_GENERATE,
    bind_llm_trace,
    record_llm_trace,
    reset_llm_trace,
)
from coco.providers.wan_image import WanImageClient

logger = logging.getLogger(__name__)


class ImageService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    async def generate(
        self,
        *,
        user: User,
        body: ImageGenerateRequest,
    ) -> ImageGenerateResponse:
        key = self._settings.aliyun_api_key
        if key is None or not key.get_secret_value().strip():
            await record_llm_trace(
                purpose=PURPOSE_IMAGE_GENERATE,
                modality="image",
                model=self._settings.image_model,
                status="skipped",
                user_id=user.id,
                error_message="未配置 API Key，生图不可用",
            )
            raise AppError(
                503,
                "image.unavailable",
                "生图服务暂时不可用。请稍后再试，刚才没有生成图片。",
            )

        tokens = bind_llm_trace(user_id=user.id)
        try:
            client = WanImageClient(
                api_key=key,
                model=self._settings.image_model,
                base_url=self._settings.aliyun_http_base_url,
            )
            result = await client.generate(
                prompt=body.prompt,
                negative_prompt=body.negative_prompt,
                size=body.size,
                n=body.n,
                watermark=body.watermark,
                seed=body.seed,
                thinking_mode=body.thinking_mode,
                prompt_extend=body.prompt_extend,
            )
        except AppError:
            raise
        except Exception:
            logger.warning("image_generate_failed", exc_info=True)
            raise AppError(
                502,
                "image.generate_failed",
                "刚才没画出来。请换个说法再试，数据没有出错写入。",
            ) from None
        finally:
            reset_llm_trace(tokens)

        return ImageGenerateResponse(
            images=[GeneratedImageItem(url=item.url) for item in result.images],
            model=result.model,
            size=result.size or body.size,
        )
