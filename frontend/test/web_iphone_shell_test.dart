import 'package:coco/core/widgets/coco_safe_area.dart';
import 'package:coco/core/widgets/web_iphone_shell.dart';
import 'package:coco/features/auth/presentation/role_selection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
