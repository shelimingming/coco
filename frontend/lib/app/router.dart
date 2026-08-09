import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/models.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/splash_page.dart';
import '../features/child/presentation/child_home_page.dart';
import '../features/child/presentation/child_settings_page.dart';
import '../features/family/presentation/child_join_page.dart';
import '../features/family/presentation/parent_family_page.dart';
import '../features/memories/presentation/memories_page.dart';
import '../features/messages/presentation/child_messages_page.dart';
import '../features/parent/presentation/parent_functions_page.dart';
import '../features/parent/presentation/parent_home_page.dart';
import '../features/parent/presentation/parent_settings_page.dart';
import '../features/reminders/presentation/new_reminder_page.dart';
import '../features/reminders/presentation/reminders_page.dart';

/// 路由只判断：是否 bootstrap、是否登录、角色是否匹配。
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (previous, next) {
    refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      if (!auth.isBootstrapped) {
        return location == '/splash' ? null : '/splash';
      }
      if (!auth.isAuthenticated) {
        return location == '/login' ? null : '/login';
      }

      final home = auth.user!.role == UserRole.parent ? '/parent' : '/child';
      if (location == '/splash' || location == '/login') {
        return home;
      }
      if (auth.user!.role == UserRole.parent && location.startsWith('/child')) {
        return '/parent';
      }
      if (auth.user!.role == UserRole.child && location.startsWith('/parent')) {
        return '/child';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/parent',
        builder: (context, state) => const ParentHomePage(),
        routes: [
          GoRoute(
            path: 'functions',
            builder: (context, state) => const ParentFunctionsPage(),
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const ParentSettingsPage(),
          ),
          GoRoute(
            path: 'family',
            builder: (context, state) => const ParentFamilyPage(),
          ),
          GoRoute(
            path: 'reminders',
            builder: (context, state) => const RemindersPage(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const NewReminderPage(),
              ),
            ],
          ),
          GoRoute(
            path: 'memories',
            builder: (context, state) => const MemoriesPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/child',
        builder: (context, state) => const ChildHomePage(),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (context, state) => const ChildSettingsPage(),
          ),
          GoRoute(
            path: 'join',
            builder: (context, state) => const ChildJoinPage(),
          ),
          GoRoute(
            path: 'messages',
            builder: (context, state) => const ChildMessagesPage(),
          ),
        ],
      ),
    ],
  );
});
