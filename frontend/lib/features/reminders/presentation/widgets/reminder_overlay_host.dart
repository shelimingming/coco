import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/coco_safe_area.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/domain/models.dart';
import '../../../notifications/application/notification_poller.dart';
import '../../../parent/application/voice_call_controller.dart';
import '../../../parent/presentation/widgets/reminder_confirm_card.dart';

/// 全局到点浮层：盖在任意父母页上，通话中不弹。
class ReminderOverlayHost extends ConsumerStatefulWidget {
  const ReminderOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ReminderOverlayHost> createState() =>
      _ReminderOverlayHostState();
}

class _ReminderOverlayHostState extends ConsumerState<ReminderOverlayHost> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(
      authControllerProvider.select(
        (state) => state.user?.role ?? state.selectedRole,
      ),
    );
    final inCall = ref.watch(
      voiceCallControllerProvider.select((state) => state.isInSession),
    );
    final pending = ref.watch(
      notificationPollerProvider.select((state) => state.pendingReminder),
    );
    final show = role == UserRole.parent && !inCall && pending != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (show)
          Positioned.fill(
            child: Material(
              color: CocoColors.neutral950.withValues(alpha: 0.45),
              child: CocoSafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CocoSpace.s5,
                    CocoSpace.s8,
                    CocoSpace.s5,
                    CocoSpace.s6,
                  ),
                  child: Center(
                    child: SingleChildScrollView(
                      child: ReminderConfirmCard(
                        notification: pending,
                        busy: _busy,
                        onConfirm: () => _run(() async {
                          await ref
                              .read(notificationPollerProvider.notifier)
                              .confirmPendingReminder();
                        }),
                        onDelay: () => _run(() async {
                          await ref
                              .read(notificationPollerProvider.notifier)
                              .delayPendingReminder();
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
