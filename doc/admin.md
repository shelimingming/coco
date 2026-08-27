# Coco 运营管理后台

独立工程目录：[`admin/`](../admin/)。与用户端 FastAPI（[`backend/`](../backend/)）**分进程**部署，共用 PostgreSQL `coco` schema。

## 启动

推荐与用户 API 一并拉起：

```bash
./scripts/dev_ios.sh --backend-only
# 或完整一键（含模拟器）：./scripts/dev_ios.sh
```

也可单独启动：

```bash
cd admin
cp .env.example .env   # 首次
uv sync
uv run uvicorn coco_admin.main:app --reload --host 127.0.0.1 --port 8001
```

| 地址 | 说明 |
| --- | --- |
| http://127.0.0.1:8001/admin | 后台入口（需登录） |
| http://127.0.0.1:8001/admin/stats | 运营总览（侧栏「运营总览」） |
| http://127.0.0.1:8001/admin/llm-debug | 模型调试（按用户搜索时间线） |
| http://127.0.0.1:8001/admin/api/stats | 统计 JSON（需已登录 session） |
| http://127.0.0.1:8001/health | 健康检查 |

开发默认账号（见 `admin/.env.example`）：

- 用户名：`admin`
- 密码：`coco-admin-dev`

生产 / staging 必须设置强 `COCO_ADMIN_PASSWORD` 与非默认 `COCO_ADMIN_SECRET_KEY`。

## 页面与能力

| 模块 | 能力 |
| --- | --- |
| 运营总览 | KPI（用户/家庭/提醒/关怀/消息/通知/语音会话）+ 近 7 日趋势图 |
| 用户 | 列表筛选；详情聚合（家庭、提醒、语音会话、关怀、消息、通知、登录会话）；禁用/启用 |
| 家庭 / 邀请 | 家庭详情聚合成员、邀请码（脱敏前 3 位）、消息、关怀 |
| 提醒 / 发生记录 | 只读浏览与状态筛选 |
| 语音会话 / 会话条目 | 只读浏览转写与工具调用；会话详情含时间线回放（含工具 JSON，无音频） |
| 模型调试 / 模型调用 | 按用户查看全部大模型调用时间线（语音 / 识图 / 标题 / 转译 / Mem0）；列表可按用途与状态筛选 |
| 关怀 / 消息 / 通知 | 只读浏览业务明文内容 |
| 登录会话 | 查看设备与吊销状态；批量吊销 |
| 验证码记录 | 仅 attempts/过期等元数据（hash 不展示，无法还原明文） |

默认业务数据**不可**新建 / 编辑 / 删除。对话历史仅运营只读查看，不提供修改或删除。

## 配置

| 变量 | 含义 |
| --- | --- |
| `COCO_DATABASE_URL` | 与 backend 相同的异步库 URL |
| `COCO_ADMIN_USERNAME` | 管理员用户名 |
| `COCO_ADMIN_PASSWORD` | 管理员密码 |
| `COCO_ADMIN_SECRET_KEY` | SQLAdmin session 签名密钥 |
| `COCO_ADMIN_ENVIRONMENT` | `development` / `staging` / `production` / `test` |
| `COCO_LLM_TRACE_ENABLED` | backend 开关，默认 true；关闭后不再写入 `llm_traces` |

## 架构要点

- 包名 `coco-admin`，依赖本地 editable 的 `coco-backend`，复用 ORM，不复制表。
- 鉴权与用户端 `parent|child` JWT **完全隔离**；`backend/` 不挂载任何 admin 路由。
- 本地建议：backend `8000`，admin `8001`。
