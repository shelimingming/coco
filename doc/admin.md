# Coco 运营管理后台

独立工程目录：[`admin/`](../admin/)。与用户端 FastAPI（[`backend/`](../backend/)）**分进程**部署，共用 PostgreSQL `coco` schema。

## 启动

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
| http://127.0.0.1:8001/admin/api/stats | 统计 JSON（需已登录 session） |
| http://127.0.0.1:8001/health | 健康检查 |

开发默认账号（见 `admin/.env.example`）：

- 用户名：`admin`
- 密码：`coco-admin-dev`

生产 / staging 必须设置强 `COCO_ADMIN_PASSWORD` 与非默认 `COCO_ADMIN_SECRET_KEY`。

## 页面与能力

| 模块 | 能力 |
| --- | --- |
| 运营总览 | KPI（用户/家庭/提醒/记忆/关怀/消息/通知）+ 近 7 日趋势图 |
| 用户 | 列表筛选；详情聚合（家庭、提醒、记忆、关怀、消息、通知、会话）；禁用/启用 |
| 家庭 / 邀请码 | 家庭详情聚合成员、邀请码、消息、关怀 |
| 提醒 / 发生记录 | 只读浏览与状态筛选 |
| 记忆 / 关怀 / 消息 / 通知 | 只读浏览业务明文内容 |
| 登录会话 | 查看设备与吊销状态；批量吊销 |
| 验证码记录 | 仅 attempts/过期等元数据（hash 不展示，无法还原明文） |

默认业务数据**不可**新建 / 编辑 / 删除。语音实时对话未落库，无聊天回放。

## 配置

| 变量 | 含义 |
| --- | --- |
| `COCO_DATABASE_URL` | 与 backend 相同的异步库 URL |
| `COCO_ADMIN_USERNAME` | 管理员用户名 |
| `COCO_ADMIN_PASSWORD` | 管理员密码 |
| `COCO_ADMIN_SECRET_KEY` | SQLAdmin session 签名密钥 |
| `COCO_ADMIN_ENVIRONMENT` | `development` / `staging` / `production` / `test` |

## 架构要点

- 包名 `coco-admin`，依赖本地 editable 的 `coco-backend`，复用 ORM，不复制表。
- 鉴权与用户端 `parent|child` JWT **完全隔离**；`backend/` 不挂载任何 admin 路由。
- 本地建议：backend `8000`，admin `8001`。
