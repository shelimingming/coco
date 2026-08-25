/// 通话中待确认动作：创建提醒或分享给子女（点卡或语音二选一）。
enum PendingVoiceActionKind { createReminder, shareToChild }

PendingVoiceActionKind? pendingVoiceActionKindFromWire(String? raw) {
  return switch (raw) {
    'create_reminder' => PendingVoiceActionKind.createReminder,
    'share_to_child' => PendingVoiceActionKind.shareToChild,
    _ => null,
  };
}

/// 服务端 action.pending 的结构化草稿，供大卡展示。
class PendingVoiceAction {
  const PendingVoiceAction({
    required this.draftId,
    required this.kind,
    this.title = '',
    this.scheduleType = 'ONCE',
    this.scheduleTime = '',
    this.repeatLabel = '',
    this.summary = '',
    this.urgency = 'LOW',
    this.shareTo = '家人',
    this.willNotifyFamily = false,
  });

  final String draftId;
  final PendingVoiceActionKind kind;
  final String title;
  final String scheduleType;
  final String scheduleTime;
  final String repeatLabel;
  final String summary;
  final String urgency;
  final String shareTo;
  final bool willNotifyFamily;

  factory PendingVoiceAction.fromPayload(Map<String, Object?> payload) {
    final kind = pendingVoiceActionKindFromWire(payload['kind'] as String?);
    if (kind == null) {
      throw FormatException('unknown pending kind');
    }
    final draftId = payload['draft_id'];
    if (draftId is! String || draftId.isEmpty) {
      throw FormatException('missing draft_id');
    }
    return PendingVoiceAction(
      draftId: draftId,
      kind: kind,
      title: (payload['title'] as String?)?.trim() ?? '',
      scheduleType: (payload['schedule_type'] as String?) ?? 'ONCE',
      scheduleTime: (payload['schedule_time'] as String?) ?? '',
      repeatLabel: (payload['repeat_label'] as String?) ?? '',
      summary: (payload['summary'] as String?)?.trim() ?? '',
      urgency: (payload['urgency'] as String?) ?? 'LOW',
      shareTo: (payload['share_to'] as String?)?.trim().isNotEmpty == true
          ? (payload['share_to'] as String).trim()
          : '家人',
      willNotifyFamily: payload['will_notify_family'] == true,
    );
  }
}
