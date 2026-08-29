import ReplayKit
import UIKit

/// 将系统屏幕帧写成 App Group 下最新 JPEG，供主 App 按需读取。
class SampleHandler: RPBroadcastSampleHandler {
  private let appGroupId = "group.com.sheliming.coco"
  private var lastWrite: CFAbsoluteTime = 0
  private let minInterval: CFAbsoluteTime = 0.5 // ~2fps，控 Extension 内存

  override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    setActive(true)
  }

  override func broadcastPaused() {
    // 保持 active，主 App 仍知共享未结束
  }

  override func broadcastResumed() {}

  override func broadcastFinished() {
    setActive(false)
    clearFrame()
  }

  override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
    guard sampleBufferType == .video else { return }
    let now = CFAbsoluteTimeGetCurrent()
    guard now - lastWrite >= minInterval else { return }
    lastWrite = now

    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
    let context = CIContext(options: [.useSoftwareRenderer: false])
    // 降采样约 720 宽
    let extent = ciImage.extent
    let scale = min(720.0 / max(extent.width, 1), 1.0)
    let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return }
    let uiImage = UIImage(cgImage: cgImage)
    guard let jpeg = uiImage.jpegData(compressionQuality: 0.7) else { return }
    writeFrame(jpeg)
  }

  private func defaults() -> UserDefaults? {
    UserDefaults(suiteName: appGroupId)
  }

  private func setActive(_ active: Bool) {
    defaults()?.set(active, forKey: "screen_share_active")
    defaults()?.synchronize()
  }

  private func writeFrame(_ data: Data) {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else { return }
    let url = container.appendingPathComponent("latest_frame.jpg")
    try? data.write(to: url, options: .atomic)
    defaults()?.set(Date().timeIntervalSince1970, forKey: "screen_share_frame_ts")
    defaults()?.synchronize()
  }

  private func clearFrame() {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else { return }
    let url = container.appendingPathComponent("latest_frame.jpg")
    try? FileManager.default.removeItem(at: url)
  }
}
