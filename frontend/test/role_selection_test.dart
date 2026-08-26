import 'package:coco/features/auth/domain/models.dart';
import 'package:coco/features/auth/presentation/role_selection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('首次身份选择展示交付文案与两项入口', (tester) async {
    UserRole? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: RoleSelectionPage(onSelected: (role) => selected = role),
      ),
    );

    expect(find.text('您好，我是AI关怀助手可可'), findsOneWidget);
    expect(find.text('您是长辈，还是子女？'), findsOneWidget);
    expect(find.text('我是长辈'), findsOneWidget);
    expect(find.text('我是子女'), findsOneWidget);

    await tester.tap(find.text('我是子女'));
    await tester.pump();
    expect(selected, UserRole.child);

    await tester.tap(find.text('我是长辈'));
    await tester.pump();
    expect(selected, UserRole.parent);
  });
}
