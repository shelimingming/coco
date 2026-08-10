import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/models.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/splash_page.dart';
import '../features/child/presentation/child_attention_page.dart';
import '../features/child/presentation/child_home_page.dart';
import '../features/child/presentation/child_shell.dart';
import '../features/family/presentation/child_family_page.dart';
import '../features/family/presentation/child_join_page.dart';
import '../features/family/presentation/parent_family_page.dart';
import '../features/history/presentation/history_detail_page.dart';
import '../features/history/presentation/history_page.dart';
import '../features/look/domain/models.dart';
import '../features/look/presentation/look_capture_page.dart';
import '../features/look/presentation/look_result_page.dart';
import '../features/memories/presentation/memories_page.dart';
import '../features/messages/presentation/child_compose_message_page.dart';
import '../features/messages/presentation/child_messages_page.dart';
import '../features/parent/presentation/parent_functions_page.dart';
import '../features/parent/presentation/parent_home_page.dart';
import '../features/parent/presentation/parent_settings_page.dart';
import '../features/reminders/presentation/new_reminder_page.dart';
import '../features/reminders/presentation/reminders_page.dart';

/// 根导航：全屏子页（加入家庭、报平安撰写）盖住底部三栏。
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// 路由只判断：是否 bootstrap、是否登录、角色是否匹配。
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (previous, next) {
    refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
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
          GoRoute(
            path: 'look',
            builder: (context, state) => const LookCapturePage(),
            routes: [
              GoRoute(
                path: 'result',
                builder: (context, state) {
                  final extra = state.extra;
                  if (extra is! LookResult) {
                    // 无结果时退回取图，避免空页
                    return const LookCapturePage();
                  }
                  return LookResultPage(result: extra);
                },
              ),
            ],
          ),
          GoRoute(
            path: 'history',
            builder: (context, state) => const HistoryPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => HistoryDetailPage(
                  conversationId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
        ],
      ),
      // 子女端：底部三栏（近况 / 留言 / 家庭）
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ChildShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/child',
                builder: (context, state) => const ChildHomePage(),
                routes: [
                  GoRoute(
                    path: 'join',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const ChildJoinPage(),
                  ),
                  GoRoute(
                    path: 'attention',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const ChildAttentionPage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/child/messages',
                builder: (context, state) => const ChildMessagesPage(),
                routes: [
                  GoRoute(
                    path: 'compose',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) =>
                        const ChildComposeMessagePage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/child/family',
                builder: (context, state) => const ChildFamilyPage(),
              ),
            ],
          ),
        ],
      ),
      // 旧设置入口并入家庭 Tab
      GoRoute(
        path: '/child/settings',
        redirect: (context, state) => '/child/family',
      ),
    ],
  );
});
