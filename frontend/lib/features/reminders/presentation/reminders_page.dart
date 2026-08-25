import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/notifications/local_notifications.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../application/reminders_providers.dart';
import '../data/reminders_api.dart';
import '../domain/models.dart';

/// 父母端提醒列表：低密度暖橙卡片，对齐交付稿气质。
class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(remindersListProvider);

    return Scaffold(
      backgroundColor: CocoColors.parentBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RemindersAppBar(
              onBack: () => context.pop(),
              // 空态已经有醒目的「新建提醒」，避免同屏重复主操作。
              onCreate: async.valueOrNull?.isNotEmpty == true
                  ? () => context.push('/parent/reminders/new')
                  : null,
            ),
            Expanded(
              child: async.when(
                loading: () => const CocoPageLoading(),
                error: (error, _) => _ErrorBody(
                  message: error is ApiException
                      ? error.message
                      : '提醒列表加载失败。您可以再试一次，数据没有丢失。',
                  onRetry: () => ref.invalidate(remindersListProvider),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return _EmptyBody(
                      onCreate: () => context.push('/parent/reminders/new'),
                    );
                  }

                  final pending = items
                      .where((r) => r.isPendingConfirm)
                      .toList();
                  final active = items.where((r) => r.isActive).toList();
                  final done = items
                      .where((r) => !r.isActive && !r.isPendingConfirm)
                      .toList();

                  return RefreshIndicator(
                    color: CocoColors.parentPrimary,
                    onRefresh: () async =>
                        ref.invalidate(remindersListProvider),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        CocoSpace.s6,
                        CocoSpace.s2,
                        CocoSpace.s6,
                        CocoSpace.s8,
                      ),
                      children: [
                        if (pending.isNotEmpty) ...[
                          const _SectionTitle('等待确认'),
                          const SizedBox(height: CocoSpace.s3),
                          ...pending.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: CocoSpace.s3,
                              ),
                              child: _PendingSuggestionCard(
                                reminder: r,
                                onAccept: () => _accept(context, ref, r),
                                onReject: () => _reject(context, ref, r),
                              ),
                            ),
                          ),
                        ],
                        if (active.isNotEmpty) ...[
                          if (pending.isNotEmpty)
                            const SizedBox(height: CocoSpace.s5),
                          const _SectionTitle('待办'),
                          const SizedBox(height: CocoSpace.s3),
                          ...active.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: CocoSpace.s3,
                              ),
                              child: _ReminderCard(
                                reminder: r,
                                onDelete: () => _delete(context, ref, r),
                              ),
                            ),
                          ),
                        ],
                        if (done.isNotEmpty) ...[
                          if (pending.isNotEmpty || active.isNotEmpty)
                            const SizedBox(height: CocoSpace.s5),
                          const _SectionTitle('已结束'),
                          const SizedBox(height: CocoSpace.s3),
                          ...done.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: CocoSpace.s3,
                              ),
                              child: _ReminderCard(
                                reminder: r,
                                muted: true,
                                onDelete: () => _delete(context, ref, r),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            CocoSpace.s6,
            CocoSpace.s2,
            CocoSpace.s6,
            CocoSpace.s5,
          ),
          child: ParentHomeButton(onPressed: () => context.go('/parent')),
        ),
      ),
    );
  }

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    Reminder reminder,
  ) async {
    try {
      await ref.read(remindersApiProvider).acceptSuggestion(reminder.id);
      ref.invalidate(remindersListProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已确认：${reminder.title}')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : '确认失败。您可以再试一次，提醒还没有生效。',
          ),
        ),
      );
    }
  }

  Future<void> _reject(
    BuildContext context,
    WidgetRef ref,
    Reminder reminder,
  ) async {
    try {
      await ref.read(remindersApiProvider).rejectSuggestion(reminder.id);
      ref.invalidate(remindersListProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已告诉家人不用这个提醒。')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : '操作失败。您可以再试一次，提醒仍在等待确认。',
          ),
        ),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Reminder reminder,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CocoColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CocoRadius.xl),
          ),
          title: const Text(
            '删除这个提醒？',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: CocoColors.neutral950,
            ),
          ),
          content: Text(
            '将删除「${reminder.title}」。删除后不可恢复，但不会影响其他提醒。',
            style: const TextStyle(
              fontSize: 22,
              height: 1.4,
              color: CocoColors.neutral700,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            CocoSpace.s5,
            0,
            CocoSpace.s5,
            CocoSpace.s5,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: CocoColors.neutral700,
                textStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
                minimumSize: const Size(64, 48),
              ),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: CocoColors.danger,
                textStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                minimumSize: const Size(64, 48),
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(remindersApiProvider).delete(reminder.id);
      // 删掉对应本地定时，避免已删除提醒仍弹系统通知
      await ref
          .read(localNotificationServiceProvider)
          .cancelReminder(reminder.id);
      ref.invalidate(remindersListProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : '删除失败。您可以再试一次，其他提醒没有受影响。',
          ),
        ),
      );
    }
  }
}

class _RemindersAppBar extends StatelessWidget {
  const _RemindersAppBar({required this.onBack, required this.onCreate});

  final VoidCallback onBack;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CocoSpace.s3),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ParentBackButton(onPressed: onBack),
            ),
            const Text(
              '提醒',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: CocoColors.neutral950,
              ),
            ),
            if (onCreate != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: CocoSpace.s2),
                  child: ParentChipButton(label: '新建', onPressed: onCreate),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: CocoColors.neutral950,
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.onDelete,
    this.muted = false,
  });

  final Reminder reminder;
  final VoidCallback onDelete;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final meta = reminder.scheduleMeta;
    final sourceLabel = reminder.isChildSuggested
        ? (reminder.suggestedByDisplayName?.isNotEmpty == true
              ? '由${reminder.suggestedByDisplayName}建议'
              : '子女建议')
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: muted ? CocoColors.neutral100 : CocoColors.parentPrimarySoft,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        boxShadow: const [
          BoxShadow(
            color: CocoColors.onboardingShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CocoSpace.s5,
          CocoSpace.s5,
          CocoSpace.s4,
          CocoSpace.s3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              reminder.title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: muted ? CocoColors.neutral700 : CocoColors.neutral950,
              ),
            ),
            const SizedBox(height: CocoSpace.s2),
            Text(
              meta,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                height: 1.3,
                color: CocoColors.neutral500,
              ),
            ),
            if (sourceLabel != null) ...[
              const SizedBox(height: CocoSpace.s1),
              Text(
                sourceLabel,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  color: CocoColors.neutral500,
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  foregroundColor: CocoColors.danger,
                  textStyle: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                  minimumSize: const Size(64, 48),
                  padding: const EdgeInsets.symmetric(horizontal: CocoSpace.s3),
                ),
                child: const Text('删除'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 子女建议、等待父母确认的卡片。
class _PendingSuggestionCard extends StatelessWidget {
  const _PendingSuggestionCard({
    required this.reminder,
    required this.onAccept,
    required this.onReject,
  });

  final Reminder reminder;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final who = reminder.suggestedByDisplayName?.isNotEmpty == true
        ? reminder.suggestedByDisplayName!
        : '家人';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: CocoColors.parentPrimarySoft,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        boxShadow: const [
          BoxShadow(
            color: CocoColors.onboardingShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              reminder.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: CocoColors.neutral950,
              ),
            ),
            const SizedBox(height: CocoSpace.s2),
            Text(
              reminder.scheduleMeta,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                height: 1.3,
                color: CocoColors.neutral500,
              ),
            ),
            const SizedBox(height: CocoSpace.s1),
            Text(
              '子女建议 · 等待确认（$who）',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: CocoColors.parentPrimary,
              ),
            ),
            const SizedBox(height: CocoSpace.s4),
            CocoPrimaryButton(label: '确认这个提醒', onPressed: onAccept),
            const SizedBox(height: CocoSpace.s3),
            CocoSecondaryButton(label: '不用了', onPressed: onReject),
          ],
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CocoSpace.s6,
        CocoSpace.s4,
        CocoSpace.s6,
        CocoSpace.s6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '还没有提醒',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: CocoColors.neutral950,
            ),
          ),
          const SizedBox(height: CocoSpace.s3),
          const Text(
            '可以回去找可可，让可可帮您记；也可以在这里手动新建。',
            style: TextStyle(
              fontSize: 22,
              height: 1.4,
              color: CocoColors.neutral700,
            ),
          ),
          const Spacer(),
          CocoPrimaryButton(label: '新建提醒', onPressed: onCreate),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CocoSpace.s6,
        CocoSpace.s4,
        CocoSpace.s6,
        CocoSpace.s6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 22,
              height: 1.4,
              color: CocoColors.neutral950,
            ),
          ),
          const Spacer(),
          CocoPrimaryButton(label: '再试一次', onPressed: onRetry),
        ],
      ),
    );
  }
}
