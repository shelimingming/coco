import 'package:coco/core/widgets/web_iphone_shell.dart';
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

    expect(padding.top, 59);
    expect(padding.bottom, 34);
  });
}
