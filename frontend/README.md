# Coco Frontend

Flutter 客户端：iOS 26 首发，并支持 Flutter Web（双角色，含实时语音）。

## iOS

```bash
flutter pub get
flutter run -d "iPhone 17 Pro"
```

或一键脚本：

```bash
./scripts/dev_ios.sh
```

## Web（Chrome）

```bash
./scripts/dev_web.sh
```

仅前端（后端已起）：

```bash
./scripts/dev_web.sh --app-only
```

手动：

```bash
flutter run -d chrome \
  --dart-define=COCO_API_BASE_URL=http://127.0.0.1:8000
```

Web 说明：

- 麦克风需要安全上下文（`localhost` 或 HTTPS）。
- 桌面以约 520px 手机壳居中；提醒不做浏览器后台定时，依赖前台轮询与站内卡片。
- 生产环境请将后端 `COCO_CORS_ALLOWED_ORIGINS` 收成具体 Web 域名（开发可用 `*`）。
- 一体上线：仓库根目录 `docker build` / `docker run`（见根 README「Docker 一体部署」）。

## API

默认 API：`http://127.0.0.1:8000`

开发验证码：`246810`（登录页会自动填入，不单独展示）。
