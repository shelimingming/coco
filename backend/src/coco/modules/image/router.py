"""文生图路由：POST /v1/image/generate。"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from coco.deps import CurrentUserDep, SettingsDep
from coco.modules.image.schemas import ImageGenerateRequest, ImageGenerateResponse
from coco.modules.image.service import ImageService

router = APIRouter(prefix="/v1/image", tags=["image"])


def get_image_service(settings: SettingsDep) -> ImageService:
    return ImageService(settings)


@router.post("/generate", response_model=ImageGenerateResponse)
async def generate_image(
    body: ImageGenerateRequest,
    user: CurrentUserDep,
    service: ImageService = Depends(get_image_service),
) -> ImageGenerateResponse:
    """文生图：返回临时图片 URL（约 24h），服务端不落盘。"""
    return await service.generate(user=user, body=body)
