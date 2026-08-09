# Coco Frontend

Flutter 客户端，首发 iOS 26。

```bash
flutter pub get
flutter run -d "iPhone 17 Pro"
```

默认 API：`http://127.0.0.1:8000`

```bash
flutter run -d "iPhone 17 Pro" \
  --dart-define=COCO_API_BASE_URL=http://127.0.0.1:8000
```

开发验证码：`246810`（登录页会显示并自动填入）。
