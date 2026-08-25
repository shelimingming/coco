import 'package:coco/features/notifications/domain/models.dart';
import 'package:coco/features/parent/presentation/widgets/reminder_confirm_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('日常提醒的确认按钮显示完成了并保留原操作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var confirmed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReminderConfirmCard(
              notification: AppNotification(
                id: 'notification-1',
                type: 'REMINDER',
                title: '日常提醒',
                body: '到「吃药」时间了，已经做过了吗？',
                payload: const {},
                createdAt: DateTime(2026, 8, 25),
              ),
              onConfirm: () => confirmed = true,
              onDelay: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('完成了'), findsOneWidget);
    expect(find.text('吃过了 / 做完了'), findsNothing);
    await tester.tap(find.text('完成了'));
    expect(confirmed, isTrue);
  });
}
