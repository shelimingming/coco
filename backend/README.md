# Coco Backend

FastAPI + SQLAlchemy 2 async + PostgreSQL（schema `coco`）。

```bash
uv sync
uv run alembic upgrade head
uv run uvicorn coco.main:app --reload --host 127.0.0.1 --port 8000
```

开发验证码：`246810`（`COCO_DEV_SMS_CODE`）。

## 实时语音（父母端）

1. 在 `.env` 配置 `COCO_ALIYUN_API_KEY`（或 `DASHSCOPE_API_KEY`），并开通 `qwen-audio-3.0-realtime-plus`。
2. `GET /v1/voice/capabilities` → `{ "realtime": true }`。
3. 父母端登录后连 `WS /v1/voice/realtime?access_token=<JWT>`。
