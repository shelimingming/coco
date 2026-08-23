import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/notifications/local_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 边到边绘制；状态栏样式由 CocoApp AnnotatedRegion 按角色覆盖
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // 尽早初始化本地通知单例，避免首条 REMINDER 来不及准备通道
  await LocalNotificationService.instance.ensureInitialized();
  runApp(const ProviderScope(child: CocoApp()));
}
