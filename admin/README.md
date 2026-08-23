# Coco Admin

运营管理后台：浏览业务数据与运营统计。独立进程，与用户端 API（`backend/`）分离，共用同一 PostgreSQL `coco` schema。

## 启动

```bash
cd admin
cp .env.example .env   # 首次
uv sync
uv run uvicorn coco_admin.main:app --reload --host 127.0.0.1 --port 8001
```

- 后台：http://127.0.0.1:8001/admin
- 健康检查：http://127.0.0.1:8001/health
- 运营总览：http://127.0.0.1:8001/admin/stats
- 模型调试：http://127.0.0.1:8001/admin/llm-debug
- 统计 JSON（需先登录拿 session cookie）：`GET /admin/api/stats`

默认开发账号见 `.env.example`（`admin` / `coco-admin-dev`）。

## 说明

- ORM 复用 `backend` 的 `coco` 包，不复制表定义。
- 业务数据默认只读；支持禁用/启用用户、吊销会话。
- 语音会话与会话条目可只读查看（转写 + 工具调用；无原始音频）。
- 模型调试页可按用户查看全部大模型调用时间线（需 backend 写入 `llm_traces`）。
- 更完整说明见 [`doc/admin.md`](../doc/admin.md)。
