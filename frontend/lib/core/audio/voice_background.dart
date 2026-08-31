import 'voice_background_stub.dart'
    if (dart.library.html) 'voice_background_web.dart'
    if (dart.library.io) 'voice_background_io.dart';

/// 后台语音保活 +（Android）悬浮狗图标。
abstract class VoiceBackground {
  /// 通话开始：Android 启麦克风前台服务；iOS 依赖 audio 后台模式。
  Future<void> startVoiceKeepAlive();

  /// 通话结束：停前台服务与浮窗。
  Future<void> stopVoiceKeepAlive();

  /// 进入后台：显示悬浮狗（Android）或本地提示（iOS）。
  /// [screenSharing] 文案区分「在听」与「在听且看屏幕」。
  Future<void> onEnteredBackground({required bool screenSharing});

  /// 回到前台：收起浮窗/提示。
  Future<void> onEnteredForeground();

  /// 是否已授予悬浮窗权限（Android）；其它平台恒 true。
  Future<bool> hasOverlayPermission();

  /// 打开系统「显示在其他应用上层」设置页（Android）。
  Future<void> requestOverlayPermission();

  /// 更新悬浮球模式：listening / watching / looking（仅 Android）。
  Future<void> updateBubbleMode(String mode);
}

VoiceBackground createVoiceBackground() => createPlatformVoiceBackground();
