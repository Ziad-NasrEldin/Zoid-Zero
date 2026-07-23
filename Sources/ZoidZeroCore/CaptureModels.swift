import CoreGraphics
import CryptoKit
import Foundation

public enum CaptureHealthState: Equatable, Sendable {
  case monitoring
  case analyzingChangedScreen
  case pausedWhileIdle
  case screenRecordingPermissionNeeded
  case captureError(String)
}

public struct VisualFingerprint: Equatable, Sendable {
  public let bytes: [UInt8]

  public init(bytes: [UInt8]) {
    self.bytes = bytes
  }

  public var identifier: String {
    SHA256.hash(data: Data(bytes)).map {
      String(format: "%02x", $0)
    }.joined()
  }

  public func isMeaningfullyDifferent(
    from other: VisualFingerprint,
    threshold: Double = 8
  ) -> Bool {
    guard bytes.count == other.bytes.count, !bytes.isEmpty else {
      return bytes != other.bytes
    }
    let totalDifference = zip(bytes, other.bytes).reduce(0) {
      $0 + abs(Int($1.0) - Int($1.1))
    }
    return Double(totalDifference) / Double(bytes.count) >= threshold
  }
}

public struct CapturedScreen: @unchecked Sendable {
  public let id: String
  public let observedAt: Date
  public let applicationName: String
  public let windowTitle: String
  public let fingerprint: VisualFingerprint
  public let image: CGImage

  public init(
    id: String,
    observedAt: Date,
    applicationName: String,
    windowTitle: String,
    fingerprint: VisualFingerprint,
    image: CGImage
  ) {
    self.id = id
    self.observedAt = observedAt
    self.applicationName = applicationName
    self.windowTitle = windowTitle
    self.fingerprint = fingerprint
    self.image = image
  }
}

public struct ScreenAnalysisResult: @unchecked Sendable {
  public let screen: CapturedScreen
  public let recognizedText: String
  public let candidates: [MeetingCandidate]

  public init(
    screen: CapturedScreen,
    recognizedText: String,
    candidates: [MeetingCandidate]
  ) {
    self.screen = screen
    self.recognizedText = recognizedText
    self.candidates = candidates
  }
}
