import 'package:wakelock_plus/wakelock_plus.dart';

/// 阻止系统按空闲时间自动熄屏。
///
/// 通话是免提、少触摸的；熄屏会把 App 送入 inactive，现有通话逻辑会当成系统打断。
/// 插件失败不得抛出，以免拖垮通话。
abstract class ScreenWakeLock {
  Future<void> enable();

  Future<void> disable();
}

/// 测试或无屏幕场景：开关都是空操作。
class NoopScreenWakeLock implements ScreenWakeLock {
  const NoopScreenWakeLock();

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

/// iOS / Android / Web：wakelock_plus（iOS idleTimer、Android 窗口 flag、Web Wake Lock）。
class WakelockPlusScreenWakeLock implements ScreenWakeLock {
  const WakelockPlusScreenWakeLock();

  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // 常亮失败时仍继续通话，只是可能随后被系统熄屏
    }
  }

  @override
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}

ScreenWakeLock createScreenWakeLock() => const WakelockPlusScreenWakeLock();
