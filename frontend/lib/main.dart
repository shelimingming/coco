import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/notifications/local_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 尽早初始化本地通知，避免首条 REMINDER 来不及准备通道
  await LocalNotificationService().ensureInitialized();
  runApp(const ProviderScope(child: CocoApp()));
}
