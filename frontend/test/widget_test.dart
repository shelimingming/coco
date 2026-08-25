import 'package:coco/core/widgets/coco_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('父母端返回按钮展示箭头和文字', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ParentBackButton(onPressed: () => tapped = true)),
      ),
    );

    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    await tester.tap(find.text('返回'));
    expect(tapped, isTrue);
  });

  testWidgets('父母端快速回首页按钮使用统一文案', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ParentHomeButton(onPressed: () => tapped = true)),
      ),
    );

    expect(find.text('回去找可可'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    await tester.tap(find.text('回去找可可'));
    expect(tapped, isTrue);
  });

  testWidgets('父母端快速回首页按钮不会挤掉页面主体', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('提醒')),
          body: const Center(child: Text('页面内容')),
          bottomNavigationBar: SafeArea(
            child: ParentHomeButton(onPressed: () {}),
          ),
        ),
      ),
    );

    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('页面内容'), findsOneWidget);
    expect(find.text('回去找可可'), findsOneWidget);
    expect(
      tester.getCenter(find.text('页面内容')).dy,
      lessThan(tester.getCenter(find.text('回去找可可')).dy),
    );
  });
}
