import CoreGraphics
import Testing

@testable import ZoidZeroInfrastructure

@Suite("User input idle detection")
struct UserInputIdleDetectorTests {
  @Test("recent mouse movement ends the idle period")
  func recentMouseMovementEndsIdlePeriod() {
    let detector = UserInputIdleDetector { eventType in
      eventType == .mouseMoved ? 0.25 : 30_000
    }

    #expect(detector.idleDuration() == 0.25)
  }
}
