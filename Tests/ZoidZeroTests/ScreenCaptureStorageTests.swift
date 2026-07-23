import CoreGraphics
import Foundation
import Testing

@testable import ZoidZeroCore
@testable import ZoidZeroInfrastructure

@Suite("Internal Screenwatch storage")
struct ScreenCaptureStorageTests {
  @Test("default root uses ZoidZero Application Support")
  func defaultRootUsesApplicationSupport() {
    let path = ScreenCaptureStorage.defaultDaysRoot.path
    #expect(
      path.hasSuffix(
        "/Library/Application Support/ZoidZero/Screenwatch/days"
      )
    )
  }

  @Test("analyzed screen writes one image and compatible JSONL metadata")
  func analyzedScreenWritesImageAndMetadata() async throws {
    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let storage = ScreenCaptureStorage(daysRoot: temporary)
    let observedAt = Date(timeIntervalSince1970: 1_753_276_496)
    let screen = CapturedScreen(
      id: "capture-1",
      observedAt: observedAt,
      applicationName: "Messages",
      windowTitle: "Conversation",
      fingerprint: VisualFingerprint(bytes: [1, 2, 3]),
      image: storageTestImage()
    )

    let imageURL = try await storage.persistAnalyzedScreen(
      ScreenAnalysisResult(
        screen: screen,
        recognizedText: "Meeting tomorrow at 3 pm",
        candidates: []
      )
    )

    #expect(FileManager.default.fileExists(atPath: imageURL.path))
    let logURL = imageURL.deletingLastPathComponent()
      .appendingPathComponent("log.jsonl")
    let log = try String(contentsOf: logURL, encoding: .utf8)
    let line = try #require(log.split(separator: "\n").first)
    let json = try #require(
      JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    )
    #expect(json["app"] as? String == "Messages")
    #expect(json["window"] as? String == "Conversation")
    #expect(json["img"] as? Bool == true)
    #expect(json["epoch"] as? Int == Int(observedAt.timeIntervalSince1970))
  }

  @Test("visual fingerprints are stable and notice meaningful changes")
  func visualFingerprintDetectsChanges() throws {
    let first = try ScreenFingerprintBuilder.make(from: storageTestImage())
    let repeated = try ScreenFingerprintBuilder.make(from: storageTestImage())
    let dark = try ScreenFingerprintBuilder.make(from: solidImage(value: 0))

    #expect(first == repeated)
    #expect(first.isMeaningfullyDifferent(from: dark))
  }

  @Test("screen recording denial is requested only once")
  func screenRecordingDenialIsNotRepeated() {
    let suite = "ZoidZeroTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let requests = PermissionRequestCounter()
    let controller = ScreenRecordingPermissionController(
      defaults: defaults,
      preflight: { false },
      request: {
        requests.increment()
        return false
      }
    )

    #expect(controller.resolve() == .denied)
    #expect(controller.resolve() == .denied)
    #expect(requests.count == 1)
  }
}

private func storageTestImage() -> CGImage {
  let bytes: [UInt8] = [
    255, 255, 255, 255,
    0, 0, 0, 255,
    0, 0, 0, 255,
    255, 255, 255, 255,
  ]
  let provider = CGDataProvider(data: Data(bytes) as CFData)!
  return CGImage(
    width: 2,
    height: 2,
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    bytesPerRow: 8,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(
      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
    provider: provider,
    decode: nil,
    shouldInterpolate: false,
    intent: .defaultIntent
  )!
}

private func solidImage(value: UInt8) -> CGImage {
  let bytes = Array(repeating: value, count: 16)
  let provider = CGDataProvider(data: Data(bytes) as CFData)!
  return CGImage(
    width: 2,
    height: 2,
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    bytesPerRow: 8,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(
      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
    provider: provider,
    decode: nil,
    shouldInterpolate: false,
    intent: .defaultIntent
  )!
}

private final class PermissionRequestCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  var count: Int {
    lock.withLock { value }
  }

  func increment() {
    lock.withLock { value += 1 }
  }
}
