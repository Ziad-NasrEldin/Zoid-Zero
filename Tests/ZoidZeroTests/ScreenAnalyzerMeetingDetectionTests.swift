import Foundation
import Testing

@testable import ZoidZeroCore
@testable import ZoidZeroInfrastructure

@Suite("Screen analyzer meeting detection")
struct ScreenAnalyzerMeetingDetectionTests {
  @Test("valid primary results bypass fallback")
  func primaryResultsBypassFallback() async throws {
    let primary = DetectorStub(result: .success([candidate(id: "primary")]))
    let fallback = DetectorStub(result: .success([candidate(id: "fallback")]))
    let analyzer = ScreenAnalyzer(primaryDetector: primary, fallbackDetector: fallback)

    let result = try await analyzer.detectMeetings(
      text: "Meeting tomorrow at 3 pm",
      personHint: "",
      observedAt: Date(),
      fingerprint: "screen"
    )

    #expect(result.map(\.id) == ["primary"])
    #expect(await primary.callCount == 1)
    #expect(await fallback.callCount == 0)
  }

  @Test("successful empty primary result does not run fallback")
  func emptyPrimaryDoesNotRunFallback() async throws {
    let primary = DetectorStub(result: .success([]))
    let fallback = DetectorStub(result: .success([candidate(id: "fallback")]))
    let analyzer = ScreenAnalyzer(primaryDetector: primary, fallbackDetector: fallback)

    let result = try await analyzer.detectMeetings(
      text: "No meeting here",
      personHint: "",
      observedAt: Date(),
      fingerprint: "screen"
    )

    #expect(result.isEmpty)
    #expect(await fallback.callCount == 0)
  }

  @Test("primary failure runs local parser fallback")
  func primaryFailureRunsFallback() async throws {
    let primary = DetectorStub(result: .failure(DetectorFailure.unavailable))
    let fallback = DetectorStub(result: .success([candidate(id: "fallback")]))
    let analyzer = ScreenAnalyzer(primaryDetector: primary, fallbackDetector: fallback)

    let result = try await analyzer.detectMeetings(
      text: "Meeting tomorrow at 3 pm",
      personHint: "",
      observedAt: Date(),
      fingerprint: "screen"
    )

    #expect(result.map(\.id) == ["fallback"])
    #expect(await fallback.callCount == 1)
  }
}

private enum DetectorFailure: Error {
  case unavailable
}

private actor DetectorStub: MeetingDetecting {
  private let result: Result<[MeetingCandidate], Error>
  private(set) var callCount = 0

  init(result: Result<[MeetingCandidate], Error>) {
    self.result = result
  }

  func detectMeetings(
    text: String,
    personHint: String,
    observedAt: Date,
    fingerprint: String
  ) throws -> [MeetingCandidate] {
    callCount += 1
    return try result.get()
  }
}

private func candidate(id: String) -> MeetingCandidate {
  MeetingCandidate(
    id: id,
    title: "Meeting",
    person: "",
    start: Date(timeIntervalSince1970: 1_753_200_000),
    sourceFingerprint: id
  )
}
