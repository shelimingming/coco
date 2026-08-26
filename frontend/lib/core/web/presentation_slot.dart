import 'presentation_slot_stub.dart'
    if (dart.library.html) 'presentation_slot_web.dart'
    as impl;

/// 双端演示页 iframe 的槽位：`parent` / `child`；普通访问为 null。
/// 仅 Web 有值，iOS / Android 恒为 null。
String? readPresentationSlot() => impl.readPresentationSlot();
