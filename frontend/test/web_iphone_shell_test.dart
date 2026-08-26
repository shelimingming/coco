import 'package:coco/core/widgets/coco_button.dart';
import 'package:coco/core/widgets/coco_safe_area.dart';
import 'package:coco/core/widgets/coco_scaffold.dart';
import 'package:coco/core/widgets/web_iphone_shell.dart';
import 'package:coco/features/auth/presentation/role_selection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('原生 App 不套 Web 外壳', () {
    expect(
      WebIphoneShell.useShellFor(
        isWeb: false,
        platform: TargetPlatform.iOS,
        viewportSize: const Size(1200, 800),
      ),
      isFalse,
    );
  });

  test('安卓 / iOS 手机浏览器不套外壳', () {
    const phone = Size(390, 844);
    expect(
      WebIphoneShell.useShellFor(
        isWeb: true,
        platform: TargetPlatform.android,
        viewportSize: phone,
      ),
      isFalse,
    );
    expect(
      WebIphoneShell.useShellFor(
        isWeb: true,
        platform: TargetPlatform.iOS,
        viewportSize: phone,
      ),
      isFalse,
    );
  });

  test('电脑宽视口才套外壳，伪装桌面 UA 的窄屏仍铺满', () {
    expect(
      WebIphoneShell.useShellFor(
        isWeb: true,
        platform: TargetPlatform.macOS,
        viewportSize: const Size(1440, 900),
      ),
      isTrue,
    );
    expect(
      WebIphoneShell.useShellFor(
        isWeb: true,
        platform: TargetPlatform.windows,
        viewportSize: const Size(390, 844),
      ),
      isFalse,
    );
  });

  test('演示页 iframe 即使窄于桌面阈值也套外壳', () {
    expect(
      WebIphoneShell.useShellFor(
        isWeb: true,
        platform: TargetPlatform.macOS,
        viewportSize: const Size(390, 700),
        inPresentationSlot: true,
      ),
      isTrue,
    );
  });

  test('演示页在手机浏览器里仍套外壳', () {
    expect(
      WebIphoneShell.useShellFor(
        isWeb: true,
        platform: TargetPlatform.iOS,
        viewportSize: const Size(390, 844),
        inPresentationSlot: true,
      ),
      isTrue,
    );
  });

  test('原生 App 即使带演示标记也不套外壳', () {
    expect(
      WebIphoneShell.useShellFor(
        isWeb: false,
        platform: TargetPlatform.iOS,
        viewportSize: const Size(390, 844),
        inPresentationSlot: true,
      ),
      isFalse,
    );
  });

  testWidgets('外壳内只改字号时仍保留 iPhone 安全区', (tester) async {
    late EdgeInsets padding;

    await tester.pumpWidget(
      MaterialApp(
        home: WebIphoneShell(
          child: Builder(
            builder: (context) {
              // 与 App 里 _ParentTextScaleCap 相同：复制当前 MediaQuery，只改字号
              final mq = MediaQuery.of(context);
              final capped = mq.textScaler.clamp(
                minScaleFactor: 1,
                maxScaleFactor: 1.4,
              );
              return MediaQuery(
                data: mq.copyWith(textScaler: capped),
                child: Builder(
                  builder: (inner) {
                    padding = MediaQuery.paddingOf(inner);
                    return const SizedBox.shrink();
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(padding.top, WebIphoneShell.topInset);
    expect(padding.bottom, WebIphoneShell.bottomInset);
  });

  testWidgets('内层把 padding 盖成 0 时 CocoSafeArea 仍避开刘海', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: WebIphoneShell(
          child: Builder(
            builder: (context) {
              // 复现：某层 MediaQuery 用错了祖先数据，把外壳安全区盖掉
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                ),
                child: const CocoSafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text('header'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final header = tester.getRect(find.text('header'));
    final island = tester.getRect(find.byKey(WebIphoneShell.islandKey));
    expect(header.top, greaterThanOrEqualTo(island.bottom));
  });

  testWidgets('身份选择气泡在外壳内低于灵动岛', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          return WebIphoneShell(
            child: Builder(
              builder: (context) {
                final mq = MediaQuery.of(context);
                return MediaQuery(
                  data: mq.copyWith(
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                    textScaler: mq.textScaler.clamp(
                      minScaleFactor: 1,
                      maxScaleFactor: 1.4,
                    ),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
            ),
          );
        },
        home: RoleSelectionPage(onSelected: (_) {}),
      ),
    );

    final bubble = tester.getRect(find.text('您好，我是AI关怀助手可可'));
    final island = tester.getRect(find.byKey(WebIphoneShell.islandKey));
    expect(bubble.top, greaterThanOrEqualTo(island.bottom));
  });

  testWidgets('CocoScaffold 有标题和底栏时不再叠出顶底大块留白', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: WebIphoneShell(
          child: CocoScaffold(
            title: '历史对话',
            bottom: ParentHomeButton(onPressed: () {}),
            body: const Text('第一条记录'),
          ),
        ),
      ),
    );

    final title = tester.getRect(find.text('历史对话'));
    final first = tester.getRect(find.text('第一条记录'));
    final home = tester.getRect(find.text('回去找可可'));
    final island = tester.getRect(find.byKey(WebIphoneShell.islandKey));

    // AppBar 已在刘海下，正文紧挨标题，不能再空出一块挡住首条
    expect(title.top, greaterThanOrEqualTo(island.bottom));
    expect(first.top - title.bottom, lessThan(48));

    // 底栏只留 Home Indicator，不能再叠一层顶安全区把按钮顶得很高
    expect(home.height, lessThan(80));
    expect(first.bottom, lessThan(home.top));
  });
}
