# Coco Backend

FastAPI + SQLAlchemy 2 async + PostgreSQL（schema `coco`）。

```bash
uv sync
uv run alembic upgrade head
uv run uvicorn coco.main:app --reload --host 127.0.0.1 --port 8000
```

开发验证码：`246810`（`COCO_DEV_SMS_CODE`）。

## 长期记忆（Mem0）

1. 数据库需先执行：`CREATE EXTENSION IF NOT EXISTS vector;`（超级用户一次即可）。
2. 配置百炼 Key 后，通话结束会异步抽取记忆到同库 pgvector collection（默认 `coco_memories`）。
3. 变更历史 SQLite 路径由 `COCO_MEM0_HISTORY_DB_PATH` 控制（默认 `.mem0/history.db`）。
4. 无 Key 或 `COCO_MEM0_ENABLED=false` 时记忆读写降级为空，不影响语音挂断。

## 对象存储（百度 BOS）

1. 在 `.env` 配置 `COCO_BOS_ACCESS_KEY_ID` / `COCO_BOS_SECRET_ACCESS_KEY`（及可选 `COCO_BOS_ENDPOINT`、`COCO_BOS_BUCKET`、`COCO_BOS_URL_TTL_SECONDS`）。
2. 业务侧使用 `from coco.providers.bos_storage import get_bos_storage`，或 FastAPI 依赖 `BosStorageDep`。
3. 每日小记配图与设置参考照存 BOS：库只存 `object_key`，接口返回签名 URL，客户端直连加载。
4. Flutter Web 直连需桶 CORS；`get_bos_storage()` 首次会写入允许 `GET/HEAD` 的跨域规则。
5. 常用方法：`put_bytes` / `put_file` / `get_bytes` / `delete` / `presigned_url`；无 Key 时 `settings.bos_available` 为 false。

## 实时语音（父母端）

1. 在 `.env` 配置 `COCO_ALIYUN_API_KEY`（或 `DASHSCOPE_API_KEY`），并开通对应模型。
2. 模型可在 `.env` 覆盖：`COCO_REALTIME_MODEL`（默认 `qwen-audio-3.0-realtime-plus`）、`COCO_TEXT_MODEL`（默认 `qwen-plus`）、`COCO_VISION_MODEL`（默认 `qwen3.7-plus`，帮我看看）、`COCO_IMAGE_MODEL`（默认 `wan2.7-image`，文生图）、`COCO_REALTIME_VOICE`（音色）。
3. `GET /v1/voice/capabilities` → `{ "realtime": true }`。
4. 父母端登录后连 `WS /v1/voice/realtime?access_token=<JWT>`。
5. 识图：`POST /v1/vision/look`（multipart `image` + 可选 `question`）→ 含 `scene_description`；图片不落库。
6. 文生图：`POST /v1/image/generate`（JSON `prompt` 等）→ 临时图片 URL（约 24h）；服务端不落盘。
7. 读图结果经 Realtime 上行 `vision.inject` 写入 `session.instructions` 并触发可可开口；追问走语音陪伴，不再依赖独立 follow-up 主路径。
8. `POST /v1/vision/follow-up` 与 ASR/TTS 仍保留，供兼容/调试；首页主路径不使用。
