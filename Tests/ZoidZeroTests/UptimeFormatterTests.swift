import Foundation
import Testing
@testable import ZoidZeroCore

struct UptimeFormatterTests {
  private let start = Date(timeIntervalSince1970: 1_000)

  @Test func formatsMinutes() {
    #expect(
      UptimeFormatter.concise(
        from: start,
        now: start.addingTimeInterval(59 * 60)
      ) == "59m"
    )
  }

  @Test func formatsHoursAndMinutes() {
    #expect(
      UptimeFormatter.concise(
        from: start,
        now: start.addingTimeInterval((16 * 60 + 16) * 60)
      ) == "16h 16m"
    )
  }

  @Test func formatsDaysWithoutGrowingTheMenuBar() {
    #expect(
      UptimeFormatter.concise(
        from: start,
        now: start.addingTimeInterval((3 * 24 * 60 + 7 * 60 + 45) * 60)
      ) == "3d 7h"
    )
  }

  @Test func clampsClockChangesBeforeLaunchToZero() {
    #expect(
      UptimeFormatter.concise(
        from: start,
        now: start.addingTimeInterval(-60)
      ) == "0m"
    )
  }
}
