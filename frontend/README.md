# Coco Frontend

Flutter 客户端：iOS 26 首发，同步支持 Android（国内真机，无 GMS）与 Flutter Web（双角色，含实时语音）。

## iOS

```bash
flutter pub get
flutter run -d "iPhone 17 Pro"
```

或一键脚本：

```bash
./scripts/dev_ios.sh
```

## Android

前置：安装 [Android Studio](https://developer.android.com/studio) 并完成 SDK / 模拟器，或连接开启 USB 调试的真机。确认：

```bash
flutter doctor
flutter devices
```

一键（后端 + admin + App）：

```bash
# 模拟器：API 默认 http://10.0.2.2:8000（宿主机）
./scripts/dev_android.sh

# USB / 局域网真机：后端听 0.0.0.0，App 走 Mac 局域网 IP
./scripts/dev_android.sh --usb
# 或
./scripts/dev_android.sh --lan
```

仅前端（后端已起）：

```bash
./scripts/dev_android.sh --app-only --lan
```

手动：

```bash
cd frontend
flutter pub get
flutter run -d <android-device-id> \
  --dart-define=COCO_API_BASE_URL=http://10.0.2.2:8000
# 真机请换成 http://<Mac局域网IP>:8000，且后端 --host 0.0.0.0
```

Android 说明：

- `applicationId`：`com.sheliming.coco`（与 iOS Bundle ID 一致）
- `minSdk`：26；Debug 允许明文 HTTP（真机连开发后端）
- 权限：麦克风、相机、相册、通知、精确闹钟；不依赖 Google Play / GMS / FCM
- 提醒：退后台走本地 `AlarmManager` 精确闹钟；国内 ROM 杀后台可能导致漏响（已知风险，后续再做厂商引导）
- 竖屏锁定；Adaptive Icon 背景 `#FFF8ED`

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
- **双端同屏演示**：一体部署时访问域名根路径会跳到 `/presentation.html`；左右 iframe 分别带 `presentation_slot=parent` / `child`，登录态互不覆盖（仅 Web `localStorage` 隔离，不影响原生）。先选身份，再自动填演示手机号并发验证码。
- 生产环境请将后端 `COCO_CORS_ALLOWED_ORIGINS` 收成具体 Web 域名（开发可用 `*`）。
- 一体上线：仓库根目录 `docker build` / `docker run`（见根 README「Docker 一体部署」）。

## API

默认 API：`http://127.0.0.1:8000`

开发验证码：`246810`（登录页会自动填入，不单独展示）。
