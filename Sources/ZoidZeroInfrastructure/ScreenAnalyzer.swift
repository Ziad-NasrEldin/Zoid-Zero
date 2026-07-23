import Foundation
import ZoidZeroCore

public actor ScreenAnalyzer {
  private let recognizer: any TextRecognizing
  private let primaryDetector: any MeetingDetecting
  private let fallbackDetector: any MeetingDetecting
  private let storage: ScreenCaptureStorage

  public init(
    recognizer: any TextRecognizing = VisionTextRecognizer(),
    primaryDetector: any MeetingDetecting = FoundationModelsMeetingDetector(),
    fallbackDetector: any MeetingDetecting = MeetingDetector(),
    storage: ScreenCaptureStorage = ScreenCaptureStorage()
  ) {
    self.recognizer = recognizer
    self.primaryDetector = primaryDetector
    self.fallbackDetector = fallbackDetector
    self.storage = storage
  }

  public func analyze(_ screen: CapturedScreen) async throws -> ScreenAnalysisResult {
    let text = try await recognizer.recognizeText(in: screen.image)
    let candidates = try await detectMeetings(
      text: text,
      personHint: screen.windowTitle,
      observedAt: screen.observedAt,
      fingerprint: screen.fingerprint.identifier
    )
    let result = ScreenAnalysisResult(
      screen: screen,
      recognizedText: text,
      candidate: candidates.first
    )
    try await storage.persistAnalyzedScreen(result)
    return result
  }

  public func detectMeetings(
    text: String,
    personHint: String,
    observedAt: Date,
    fingerprint: String
  ) async throws -> [MeetingCandidate] {
    do {
      return try await primaryDetector.detectMeetings(
        text: text,
        personHint: personHint,
        observedAt: observedAt,
        fingerprint: fingerprint
      )
    } catch {
      return try await fallbackDetector.detectMeetings(
        text: text,
        personHint: personHint,
        observedAt: observedAt,
        fingerprint: fingerprint
      )
    }
  }
}
