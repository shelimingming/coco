import 'voice_background.dart';

/// Web：无后台保活 / 悬浮窗。
VoiceBackground createPlatformVoiceBackground() => _WebVoiceBackground();

class _WebVoiceBackground implements VoiceBackground {
  @override
  Future<void> startVoiceKeepAlive() async {}

  @override
  Future<void> stopVoiceKeepAlive() async {}

  @override
  Future<void> onEnteredBackground({required bool screenSharing}) async {}

  @override
  Future<void> onEnteredForeground() async {}

  @override
  Future<bool> hasOverlayPermission() async => true;

  @override
  Future<void> requestOverlayPermission() async {}
}
