# 可可 Coco

面向老人与子女的 AI 家庭陪伴助手。

- 产品需求：[`doc/需求.md`](doc/需求.md)
- 架构约定：[`doc/架构.md`](doc/架构.md)
- 设计规范：[`doc/DESIGN.md`](doc/DESIGN.md)
- 帮我看看（父母端识图）：[`doc/帮我看看.md`](doc/帮我看看.md)
- 运营后台：[`doc/admin.md`](doc/admin.md) / [`admin/`](admin/)
- 旧实现（只读）：[`back/`](back/)

## 环境要求

- Python 3.12+，[uv](https://github.com/astral-sh/uv)
- Flutter 3.44+ / Dart 3.12+
- PostgreSQL（本地已有 `coco` 库即可）
- Xcode + iOS 26 模拟器（部署目标 iOS 26）

## 一键启动（推荐）

```bash
./scripts/dev_ios.sh
```

依次完成：生成 `backend/.env` / `admin/.env` → 数据库预检 → `uv sync` → `alembic upgrade head` → 启动用户 API（8000）与运营后台（8001）并等健康检查 → 启动 iOS 26 模拟器 → `flutter run`。
服务已在跑时可加 `--reuse-backend` 复用；`flutter run` 退出时脚本会顺手关掉自己拉起的服务。

常用参数：

| 参数 | 作用 |
| --- | --- |
| `--list` | 列出该 iOS 版本下的候选模拟器 |
| `--dual` | 同时起两台模拟器并各跑一份 App，方便父母/子女双角色联调 |
| `--device "iPhone 17"` | 指定机型（名称或 UDID），默认 iPhone 17 Pro；可写两次配双端 |
| `--ios 26` | 指定 iOS 大版本（默认 26） |
| `--lan` | 真机调试：后端监听 `0.0.0.0`，App 用 Mac 局域网 IP |
| `--backend-only` / `--app-only` | 只起 API+admin / 只起 App |
| `--no-admin` | 不起运营后台 |
| `--restart-backend` | 重启已占用端口的后端 |
| `--port 8002` | 换用户 API 端口（默认 8000；勿与 admin 冲突） |
| `--admin-port 8002` | 换运营后台端口（默认 8001） |

双角色联调示例：

```bash
./scripts/dev_ios.sh --dual
# 或指定两台机型
./scripts/dev_ios.sh --dual --device "iPhone 17 Pro" --device "iPhone 17"
```

默认会启动两台（优先 `iPhone 17 Pro` + `iPhone 17`）：统一 `flutter build` 一次，再分别安装启动。构建日志在 `.dev/flutter-build.log`。两台会话本地隔离，可各登一个角色。

日志与 PID：`.dev/backend.log` / `.dev/backend.pid`，`.dev/admin.log` / `.dev/admin.pid`。

下面是手动分步启动的方式。

## 后端

```bash
cd backend
cp .env.example .env   # 首次
uv sync
uv run alembic upgrade head
uv run uvicorn coco.main:app --reload --host 127.0.0.1 --port 8000
```

- 文档：http://127.0.0.1:8000/docs
- 开发验证码固定为 `246810`（见 `COCO_DEV_SMS_CODE`）

## 运营管理后台

独立进程，与用户 API 分离，共用同一数据库：

```bash
cd admin
cp .env.example .env   # 首次
uv sync
uv run uvicorn coco_admin.main:app --reload --host 127.0.0.1 --port 8001
```

- 后台：http://127.0.0.1:8001/admin
- 默认开发账号见 `admin/.env.example`
- 说明：[`doc/admin.md`](doc/admin.md)

## 前端（iOS 模拟器）

```bash
cd frontend
flutter pub get
flutter run -d "iPhone 17 Pro"
```

默认 API：`http://127.0.0.1:8000`。覆盖方式：

```bash
flutter run -d "iPhone 17 Pro" \
  --dart-define=COCO_API_BASE_URL=http://127.0.0.1:8000
```

真机请改成 Mac 局域网 IP。

## Web（本地）

```bash
./scripts/dev_web.sh
```

详见 [`frontend/README.md`](frontend/README.md)。

## 虚机增量更新（无 Docker）

首次部署完成后，用脚本把本机改动同步到虚机（默认 `106.13.135.10`，对外 **80**）：

```bash
./scripts/deploy_vm.sh                 # 前后端
./scripts/deploy_vm.sh --backend-only  # 只后端
./scripts/deploy_vm.sh --web-only      # 只 Web
./scripts/deploy_vm.sh --host IP       # 换机器
```

需本机已能 `ssh root@虚机`（建议密钥登录）。远端目录：`/opt/coco`，服务名：`coco`，访问：`http://虚机IP/`（安全组放行 80）。

## Docker 一体部署（Web + API）

前后端打进同一镜像：FastAPI 提供 `/v1`、`/health`，并托管 Flutter Web。数据库用**外部 Postgres**。

```bash
cp docker.env.example docker.env
# 编辑 docker.env：必填 COCO_DATABASE_URL（及密钥等）

docker build -t coco:latest .
docker run --rm -p 8000:8000 --env-file docker.env \
  --add-host=host.docker.internal:host-gateway \
  coco:latest
```

- 应用：http://127.0.0.1:8000
- 健康检查：http://127.0.0.1:8000/health
- 开发验证码：`246810`（`COCO_SMS_PROVIDER=dev` 时）
- 启动时会执行 `alembic upgrade head`；库与账号需事先就绪
- 连本机 Postgres：`COCO_DATABASE_URL` 主机用 `host.docker.internal`（上面 `--add-host` 在 Linux 上也可用；Docker Desktop / macOS 通常自带）

上线注意：

1. `COCO_ENVIRONMENT=production` 时禁止 `SMS_PROVIDER=dev` 与含 `local-development` 的密钥。
2. 配置 `COCO_ALIYUN_API_KEY` 以启用实时语音 / 识图。
3. 公网务必在前面加 HTTPS 反向代理（麦克风需要安全上下文）；同源部署可保持 `COCO_CORS_ALLOWED_ORIGINS=*`。
4. 若 Web 与 API 不同域，构建时传入：

```bash
docker build --build-arg COCO_API_BASE_URL=https://api.example.com -t coco:latest .
```

## 本期范围

- 前后端骨架
- 手机号验证码登录
- 父母端 / 子女端占位首页

语音、提醒、记忆、家庭绑定等后续再加。
