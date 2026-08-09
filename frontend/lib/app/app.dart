import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/models.dart';
import 'router.dart';

class CocoApp extends ConsumerWidget {
  const CocoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // 未登录时跟选择的身份走，避免子女登录页仍套父母暖色主题
    final role = ref.watch(
      authControllerProvider.select(
        (state) => state.user?.role ?? state.selectedRole,
      ),
    );

    return MaterialApp.router(
      title: '可可',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: role == UserRole.child ? CocoTheme.child() : CocoTheme.parent(),
      routerConfig: router,
    );
  }
}
