# 可可 Coco

面向老人与子女的 AI 家庭陪伴助手。

- 产品需求：[`doc/需求.md`](doc/需求.md)
- 架构约定：[`doc/架构.md`](doc/架构.md)
- 设计规范：[`doc/DESIGN.md`](doc/DESIGN.md)
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

依次完成：生成 `backend/.env` → 数据库预检 → `uv sync` → `alembic upgrade head` → 启动 uvicorn 并等健康检查 → 启动 iOS 26 模拟器 → `flutter run`。
后端已在跑时会直接复用；`flutter run` 退出时脚本会顺手关掉自己拉起的后端。

常用参数：

| 参数 | 作用 |
| --- | --- |
| `--list` | 列出该 iOS 版本下的候选模拟器 |
| `--dual` | 同时起两台模拟器并各跑一份 App，方便父母/子女双角色联调 |
| `--device "iPhone 17"` | 指定机型（名称或 UDID），默认 iPhone 17 Pro；可写两次配双端 |
| `--ios 26` | 指定 iOS 大版本（默认 26） |
| `--lan` | 真机调试：后端监听 `0.0.0.0`，App 用 Mac 局域网 IP |
| `--backend-only` / `--app-only` | 只起后端 / 只起 App |
| `--restart-backend` | 重启已占用端口的后端 |
| `--port 8001` | 换后端端口 |

双角色联调示例：

```bash
./scripts/dev_ios.sh --dual
# 或指定两台机型
./scripts/dev_ios.sh --dual --device "iPhone 17 Pro" --device "iPhone 17"
```

默认会启动两台（优先 `iPhone 17 Pro` + `iPhone 17`）：统一 `flutter build` 一次，再分别安装启动。构建日志在 `.dev/flutter-build.log`。两台会话本地隔离，可各登一个角色。

后端日志在 `.dev/backend.log`，PID 在 `.dev/backend.pid`。

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

## 本期范围

- 前后端骨架
- 手机号验证码登录
- 父母端 / 子女端占位首页

语音、提醒、记忆、家庭绑定等后续再加。
