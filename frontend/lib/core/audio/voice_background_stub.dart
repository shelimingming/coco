import 'voice_background.dart';

VoiceBackground createPlatformVoiceBackground() => _NoopVoiceBackground();

class _NoopVoiceBackground implements VoiceBackground {
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
