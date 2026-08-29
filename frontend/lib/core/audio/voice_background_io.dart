import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'voice_background.dart';

/// iOS / Android：MethodChannel +（iOS）本地通知提示。
VoiceBackground createPlatformVoiceBackground() => IoVoiceBackground();

class IoVoiceBackground implements VoiceBackground {
  static const _channel = MethodChannel('coco/voice_background');
  static const _iosHintId = 0xC0C1;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _iosReady = false;

  Future<void> _ensureIosNotif() async {
    if (_iosReady || !Platform.isIOS) return;
    const init = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: init);
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: false, sound: false);
    _iosReady = true;
  }

  @override
  Future<void> startVoiceKeepAlive() async {
    try {
      await _channel.invokeMethod<void>('startVoiceKeepAlive');
    } on PlatformException {
      // 忽略：插件未注册时不影响前台通话
    } on MissingPluginException {
      // Web / 未实现
    }
  }

  @override
  Future<void> stopVoiceKeepAlive() async {
    try {
      await _channel.invokeMethod<void>('stopVoiceKeepAlive');
    } on PlatformException {
      // 已停或未启动
    } on MissingPluginException {
      // 忽略
    }
    await onEnteredForeground();
  }

  @override
  Future<void> onEnteredBackground({required bool screenSharing}) async {
    try {
      await _channel.invokeMethod<void>('showBubble', {
        'screenSharing': screenSharing,
      });
    } on PlatformException {
      // 无悬浮窗权限时依赖通知
    } on MissingPluginException {
      // 忽略
    }

    if (Platform.isIOS) {
      try {
        await _ensureIosNotif();
        final body = screenSharing
            ? '可可还在听，也可以看你的屏幕。点通知可回可可。'
            : '可可还在听。点通知可回可可继续说。';
        await _plugin.show(
          id: _iosHintId,
          title: '可可陪你呢',
          body: body,
          notificationDetails: const NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBanner: true,
              presentSound: false,
            ),
          ),
        );
      } catch (_) {
        // 通知权限未开时静默
      }
    }
  }

  @override
  Future<void> onEnteredForeground() async {
    try {
      await _channel.invokeMethod<void>('hideBubble');
    } on PlatformException {
      // 忽略
    } on MissingPluginException {
      // 忽略
    }

    if (Platform.isIOS && _iosReady) {
      try {
        await _plugin.cancel(id: _iosHintId);
      } catch (_) {}
    }
  }

  @override
  Future<bool> hasOverlayPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('hasOverlayPermission');
      return ok == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestOverlayPermission');
    } on PlatformException {
      // 忽略
    } on MissingPluginException {
      // 忽略
    }
  }
}
