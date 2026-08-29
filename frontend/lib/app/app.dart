import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/web_iphone_shell.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/models.dart';
import '../features/notifications/application/notification_poller.dart';
import '../features/parent/application/voice_call_controller.dart';
import '../features/reminders/presentation/widgets/reminder_overlay_host.dart';
import 'router.dart';

class CocoApp extends ConsumerWidget {
  const CocoApp({super.key});

  /// 父母端系统字号上限，避免超大字体撑破首页主按钮。
  static const double _parentTextScaleCap = 1.4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // 未登录时跟选择的身份走，避免子女登录页仍套父母暖色主题
    final role = ref.watch(
      authControllerProvider.select(
        (state) => state.user?.role ?? state.selectedRole,
      ),
    );
    // 全局挂载通知轮询：登录后前台拉未读并弹本地系统通知
    ref.watch(notificationPollerProvider);

    // 语音 open_screen：会话跨页保留，由根层执行 go
    ref.listen<String?>(voicePendingNavigateProvider, (previous, next) {
      if (next == null || next.isEmpty) return;
      router.go(next);
      ref.read(voicePendingNavigateProvider.notifier).state = null;
    });

    final isChild = role == UserRole.child;
    final scaffoldBg = isChild
        ? CocoColors.childBackground
        : CocoColors.parentBackground;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 边到边：透明状态栏 + 深色图标，适配暖米 / 青绿浅色底
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: scaffoldBg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MaterialApp.router(
        title: '可可',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: isChild ? CocoTheme.child() : CocoTheme.parent(),
        routerConfig: router,
        builder: (context, child) {
          var content = child ?? const SizedBox.shrink();
          if (!isChild) {
            // 到点浮层盖在任意父母页上，不绑死在首页
            content = ReminderOverlayHost(child: content);
            // 必须包在外壳内侧：用当前 MediaQuery 只改字号。
            // 若用 builder 的桌面 MediaQuery，会把 iPhone 外壳的安全区盖成 0，顶底文字贴边被裁。
            content = _ParentTextScaleCap(child: content);
          }
          // 电脑 Web 套 iPhone 外框预览；手机浏览器铺满，避免套娃小屏
          if (!WebIphoneShell.enabledOf(context)) return content;
          return WebIphoneShell(child: content);
        },
      ),
    );
  }
}

/// 父母端字号上限：复制最近的 MediaQuery，只改 textScaler。
class _ParentTextScaleCap extends StatelessWidget {
  const _ParentTextScaleCap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final capped = mq.textScaler.clamp(
      minScaleFactor: 1,
      maxScaleFactor: CocoApp._parentTextScaleCap,
    );
    return MediaQuery(
      data: mq.copyWith(textScaler: capped),
      child: child,
    );
  }
}
