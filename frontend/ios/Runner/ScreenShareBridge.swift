import Flutter
import ReplayKit
import UIKit

/// 看手机：读 App Group 最新帧；等待 Broadcast Extension 启动。
enum ScreenShareBridge {
  static let appGroupId = "group.com.sheliming.coco"
  static let channelName = "coco/screen_share"
  static let pickerViewType = "coco/broadcast_picker"

  static func register(messenger: FlutterBinaryMessenger, registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    var pollTimer: Timer?
    var pendingStart: FlutterResult?

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        // 清旧状态，轮询 Extension 是否已开始广播
        setActiveFlag(false)
        clearFrameFile()
        pendingStart?(false)
        pendingStart = result
        pollTimer?.invalidate()
        let startedAt = Date()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
          if isActive() {
            timer.invalidate()
            pollTimer = nil
            pendingStart?(true)
            pendingStart = nil
            return
          }
          if Date().timeIntervalSince(startedAt) > 90 {
            timer.invalidate()
            pollTimer = nil
            pendingStart?(false)
            pendingStart = nil
          }
        }
      case "stop":
        pollTimer?.invalidate()
        pollTimer = nil
        pendingStart?(false)
        pendingStart = nil
        setActiveFlag(false)
        clearFrameFile()
        // 无法从主 App 强制停系统广播；清本地状态即可，用户可在控制中心结束
        result(nil)
      case "captureLatestFrame":
        result(readFrameData())
      case "isCapturing":
        result(isActive())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    registrar.register(
      BroadcastPickerFactory(messenger: messenger),
      withId: pickerViewType
    )
  }

  private static func defaults() -> UserDefaults? {
    UserDefaults(suiteName: appGroupId)
  }

  private static func setActiveFlag(_ active: Bool) {
    defaults()?.set(active, forKey: "screen_share_active")
    defaults()?.synchronize()
  }

  static func isActive() -> Bool {
    defaults()?.bool(forKey: "screen_share_active") ?? false
  }

  static func readFrameData() -> FlutterStandardTypedData? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else { return nil }
    let url = container.appendingPathComponent("latest_frame.jpg")
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    return FlutterStandardTypedData(bytes: data)
  }

  private static func clearFrameFile() {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else { return }
    let url = container.appendingPathComponent("latest_frame.jpg")
    try? FileManager.default.removeItem(at: url)
  }
}

/// 系统广播选择器：透明盖在大按钮上，点击即弹出「选可可 → 开始直播」。
final class BroadcastPickerFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    BroadcastPickerPlatformView(frame: frame)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class BroadcastPickerPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    super.init()

    let picker = RPSystemBroadcastPickerView(frame: container.bounds)
    picker.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // 预选可可看手机扩展
    picker.preferredExtension = "com.sheliming.coco.ScreenShareExtension"
    picker.showsMicrophoneButton = false
    // 放大点击热区：遍历子按钮拉大
    for sub in picker.subviews {
      if let btn = sub as? UIButton {
        btn.setImage(nil, for: .normal)
        btn.setTitle("开始看手机", for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(red: 0.91, green: 0.45, blue: 0.22, alpha: 1)
        btn.layer.cornerRadius = 16
        btn.contentEdgeInsets = UIEdgeInsets(top: 16, left: 24, bottom: 16, right: 24)
      }
    }
    container.addSubview(picker)
  }

  func view() -> UIView {
    container
  }
}
