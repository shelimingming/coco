# Coco Backend

FastAPI + SQLAlchemy 2 async + PostgreSQL（schema `coco`）。

```bash
uv sync
uv run alembic upgrade head
uv run uvicorn coco.main:app --reload --host 127.0.0.1 --port 8000
```

开发验证码：`246810`（`COCO_DEV_SMS_CODE`）。

## 实时语音（父母端）

1. 在 `.env` 配置 `COCO_ALIYUN_API_KEY`（或 `DASHSCOPE_API_KEY`），并开通对应模型。
2. 模型可在 `.env` 覆盖：`COCO_REALTIME_MODEL`（默认 `qwen-audio-3.0-realtime-plus`）、`COCO_TEXT_MODEL`（默认 `qwen-plus`）、`COCO_VISION_MODEL`（默认 `qwen3.7-plus`，帮我看看）、`COCO_REALTIME_VOICE`（音色）。
3. `GET /v1/voice/capabilities` → `{ "realtime": true }`。
4. 父母端登录后连 `WS /v1/voice/realtime?access_token=<JWT>`。
5. 识图：`POST /v1/vision/look`（multipart `image` + 可选 `question`）；图片不落库。
