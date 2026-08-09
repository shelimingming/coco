"""语音能力相关响应模型。"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class FrozenModel(BaseModel):
    model_config = ConfigDict(frozen=True)


class VoiceCapabilitiesResponse(FrozenModel):
    """客户端据此决定是否展示实时通话入口。"""

    realtime: bool
