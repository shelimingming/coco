import 'package:coco/features/care/domain/models.dart';
import 'package:coco/features/family/domain/models.dart';
import 'package:coco/features/memories/domain/models.dart';
import 'package:coco/features/messages/domain/models.dart';
import 'package:coco/features/notifications/application/notification_poller.dart';
import 'package:coco/features/notifications/domain/models.dart';
import 'package:coco/features/reminders/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Reminder.fromJson', () {
    test('parses schedule time label', () {
      final reminder = Reminder.fromJson({
        'id': 'r1',
        'title': '吃药',
        'schedule_type': 'DAILY',
        'schedule_time': '20:00:00',
        'status': 'ACTIVE',
        'created_source': 'PARENT',
        'next_trigger_at': '2026-08-09T12:00:00Z',
        'created_at': '2026-08-09T03:00:00Z',
      });
      expect(reminder.timeLabel, '20:00');
      expect(reminder.isDaily, isTrue);
      expect(reminder.isActive, isTrue);
    });
  });

  group('ChildToday', () {
    test('maps NEED_CONTACT status and attention items', () {
      final today = ChildToday.fromJson({
        'status': 'NEED_CONTACT',
        'headline': '建议联系父母',
        'needs_contact_reason': '今天有提醒仍未确认',
        'attention_items': [
          {
            'id': 'c1',
            'parent_id': 'p1',
            'child_id': 'ch1',
            'summary': '今天腿有些酸',
            'urgency': 'LOW',
            'reply_expectation': 'WHEN_AVAILABLE',
            'source': 'PARENT_CONVERSATION',
            'parent_confirmed': true,
            'read_at': null,
            'created_at': '2026-08-09T03:00:00Z',
          },
        ],
        'reminder_items': [
          {
            'title': '吃药',
            'state': 'ESCALATED',
            'due_at': '2026-08-09T01:00:00Z',
          },
        ],
      });
      expect(today.status, ChildTodayStatus.needContact);
      expect(today.attentionItems.single.summary, '今天腿有些酸');
      expect(today.reminderItems.single.state, 'ESCALATED');
    });
  });

  group('MessagePreview', () {
    test('keeps translated flag honest', () {
      final preview = MessagePreview.fromJson({
        'original_text': '吃过饭了',
        'delivered_text': '吃过饭了',
        'translated': false,
      });
      expect(preview.translated, isFalse);
    });
  });

  group('Memory category label', () {
    test('maps PREFERENCE', () {
      final memory = Memory.fromJson({
        'id': 'm1',
        'content': '喜欢晚饭后散步',
        'category': 'PREFERENCE',
        'source': 'PARENT',
        'confirmed': true,
        'created_at': '2026-08-09T03:00:00Z',
        'updated_at': '2026-08-09T03:00:00Z',
      });
      expect(memory.categoryLabel, '喜好');
    });
  });

  group('FamilyInvite', () {
    test('parses code', () {
      final invite = FamilyInvite.fromJson({
        'code': '123456',
        'expires_at': '2026-08-09T03:10:00Z',
        'family_id': 'f1',
      });
      expect(invite.code, '123456');
    });
  });

  group('AppNotification', () {
    test('exposes reminder payload ids', () {
      final n = AppNotification.fromJson({
        'id': 'n1',
        'type': 'REMINDER',
        'title': '日常提醒',
        'body': '到吃药时间了',
        'payload': {
          'reminder_id': 'r1',
          'occurrence_id': 'o1',
        },
        'read_at': null,
        'created_at': '2026-08-09T03:00:00Z',
      });
      expect(n.isReminder, isTrue);
      expect(n.reminderId, 'r1');
      expect(n.occurrenceId, 'o1');
    });
  });

  group('filterUnseenNotificationIds', () {
    test('dedupes seen ids', () {
      final unseen = filterUnseenNotificationIds(
        incomingIds: ['a', 'b', 'c'],
        seenIds: {'b'},
      );
      expect(unseen, {'a', 'c'});
    });
  });
}
