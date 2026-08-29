"""帮我看看路由：multipart 上传图片，图片不落盘。"""

from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, UploadFile

from coco.deps import CurrentUserDep, SessionDep, SettingsDep
from coco.errors import AppError
from coco.modules.vision.schemas import (
    LookFollowUpRequest,
    LookFollowUpResponse,
    LookResponse,
)
from coco.modules.vision.service import VisionService

router = APIRouter(prefix="/v1/vision", tags=["vision"])


def get_vision_service(settings: SettingsDep) -> VisionService:
    return VisionService(settings)


@router.post("/look", response_model=LookResponse)
async def look_image(
    session: SessionDep,
    user: CurrentUserDep,
    service: VisionService = Depends(get_vision_service),
    image: UploadFile = File(..., description="要看的照片"),
    question: str | None = Form(default=None),
    source: str | None = Form(default=None),
) -> LookResponse:
    """父母端识图：只转发内存中的图片字节，请求结束即丢弃（追问用进程内缓存）。"""
    try:
        image_bytes = await image.read()
    except Exception as exc:
        raise AppError(
            400,
            "vision.read_failed",
            "照片读取失败。请重新拍一张。数据没有保存。",
        ) from exc

    cleaned_question = (question or "").strip() or None
    if cleaned_question and len(cleaned_question) > 200:
        raise AppError(
            400,
            "vision.question_too_long",
            "问题太长了。请用一两句话说清楚想问什么。",
        )

    cleaned_source = (source or "").strip().lower() or None
    if cleaned_source and cleaned_source not in {
        "camera",
        "album",
        "screenshot",
        "screen",
    }:
        cleaned_source = None

    return await service.look(
        session,
        user=user,
        image_bytes=image_bytes,
        content_type=image.content_type,
        question=cleaned_question,
        source=cleaned_source,
    )


@router.post("/follow-up", response_model=LookFollowUpResponse)
async def look_follow_up(
    body: LookFollowUpRequest,
    session: SessionDep,
    user: CurrentUserDep,
    service: VisionService = Depends(get_vision_service),
) -> LookFollowUpResponse:
    """同图多轮追问：继续用识图模型，不切实时语音。"""
    return await service.follow_up(
        session,
        user=user,
        conversation_id=body.conversation_id,
        text=body.text,
    )
