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

    test('parses child suggestion pending confirm', () {
      final reminder = Reminder.fromJson({
        'id': 'r2',
        'title': '喝水',
        'schedule_type': 'ONCE',
        'schedule_time': '09:30:00',
        'status': 'PENDING_CONFIRM',
        'created_source': 'CHILD',
        'next_trigger_at': null,
        'created_at': '2026-08-12T03:00:00Z',
        'suggested_by_user_id': 'c1',
        'suggested_by_display_name': '小明',
      });
      expect(reminder.isPendingConfirm, isTrue);
      expect(reminder.isChildSuggested, isTrue);
      expect(reminder.scheduleMeta, '一次 09:30');
      expect(reminder.suggestedByDisplayName, '小明');
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

  group('Memory', () {
    test('parses content without category', () {
      final memory = Memory.fromJson({
        'id': 'm1',
        'content': '喜欢晚饭后散步',
        'created_at': '2026-08-09T03:00:00Z',
        'updated_at': '2026-08-09T03:00:00Z',
      });
      expect(memory.id, 'm1');
      expect(memory.content, '喜欢晚饭后散步');
      expect(memory.createdAt, isNotNull);
      expect(memory.categoryLabel, '其他');
    });

    test('maps category labels', () {
      final memory = Memory.fromJson({
        'id': 'm2',
        'content': '女儿叫小林',
        'category': 'FAMILY',
        'source': 'VOICE',
      });
      expect(memory.categoryLabel, '家人');
    });
  });

  group('FamilyInvite', () {
    test('parses invite link fields', () {
      final invite = FamilyInvite.fromJson({
        'token': 'abc-token',
        'invite_url': 'https://coco.xyfit.top/invite/abc-token',
        'family_id': 'f1',
      });
      expect(invite.token, 'abc-token');
      expect(invite.inviteUrl, contains('/invite/'));
    });
  });

  group('FamilyInvitePreview', () {
    test('parses preview', () {
      final preview = FamilyInvitePreview.fromJson({
        'inviter_display_name': '张阿姨',
        'target_role': 'child',
        'valid': true,
      });
      expect(preview.inviterDisplayName, '张阿姨');
      expect(preview.targetRole, 'child');
    });
  });

  group('AppNotification', () {
    test('exposes reminder payload ids', () {
      final n = AppNotification.fromJson({
        'id': 'n1',
        'type': 'REMINDER',
        'title': '日常提醒',
        'body': '到吃药时间了',
        'payload': {'reminder_id': 'r1', 'occurrence_id': 'o1'},
        'read_at': null,
        'created_at': '2026-08-09T03:00:00Z',
      });
      expect(n.isReminder, isTrue);
      expect(n.reminderId, 'r1');
      expect(n.occurrenceId, 'o1');
    });
  });

  group('ReminderOccurrence.fromJson', () {
    test('parses dual delivery and response fields', () {
      final occ = ReminderOccurrence.fromJson({
        'id': 'o1',
        'reminder_id': 'r1',
        'due_at': '2026-08-09T12:00:00Z',
        'delivery_state': 'NOTIFIED_1',
        'response_status': 'NONE',
        'reminder_revision': 1,
        'title_snapshot': '吃药',
        'snooze_until': null,
        'attempt_count': 1,
        'response_source': 'NONE',
        'first_notified_at': '2026-08-09T12:00:00Z',
        'second_notified_at': null,
        'confirmed_at': null,
        'escalated_at': null,
      });
      expect(occ.isOpen, isTrue);
      expect(occ.deliveryState, 'NOTIFIED_1');
      expect(occ.responseStatus, 'NONE');
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

  group('shouldSkipReminderBanner', () {
    final bg = DateTime.utc(2026, 8, 12, 12, 0);
    test('skips when scheduled while backgrounded', () {
      expect(
        shouldSkipReminderBanner(
          skipIfScheduled: true,
          reminderId: 'r1',
          scheduledReminderIds: {'r1'},
          backgroundedAt: bg,
          createdAt: bg.add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
    });

    test('does not skip older notifications', () {
      expect(
        shouldSkipReminderBanner(
          skipIfScheduled: true,
          reminderId: 'r1',
          scheduledReminderIds: {'r1'},
          backgroundedAt: bg,
          createdAt: bg.subtract(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });
  });
}
