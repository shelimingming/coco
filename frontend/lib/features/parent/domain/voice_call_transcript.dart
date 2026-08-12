/// 本通会话里的一条转写：用户或可可。
enum VoiceCallTranscriptRole { user, assistant }

class VoiceCallTranscriptEntry {
  const VoiceCallTranscriptEntry({required this.role, required this.text});

  final VoiceCallTranscriptRole role;
  final String text;

  bool get isUser => role == VoiceCallTranscriptRole.user;

  VoiceCallTranscriptEntry copyWith({String? text}) {
    return VoiceCallTranscriptEntry(role: role, text: text ?? this.text);
  }
}
