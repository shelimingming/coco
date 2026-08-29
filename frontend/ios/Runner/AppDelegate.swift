import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 前台也展示横幅/声音；FlutterAppDelegate 已实现 UNUserNotificationCenterDelegate
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 看手机：MethodChannel + 广播选择器 PlatformView
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "coco.ScreenShareBridge")
    if let registrar {
      ScreenShareBridge.register(
        messenger: registrar.messenger(),
        registrar: registrar
      )
    }
  }
}
