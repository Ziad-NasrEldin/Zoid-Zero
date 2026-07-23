import Foundation
import Testing

@testable import ZoidZeroCore
@testable import ZoidZeroInfrastructure

@Suite("Application activity tracking")
struct ApplicationActivityTrackerTests {
  private let start = Date(timeIntervalSince1970: 1_753_200_000)
  private let safari = ApplicationIdentity(
    bundleIdentifier: "com.apple.Safari",
    displayName: "Safari"
  )
  private let mail = ApplicationIdentity(
    bundleIdentifier: "com.apple.mail",
    displayName: "Mail"
  )

  @Test("application switches create non-overlapping intervals")
  func applicationSwitchesCreateIntervals() async {
    let store = ActivityStoreSpy()
    let tracker = ApplicationActivityTracker(store: store)

    await tracker.transition(to: safari, at: start)
    await tracker.transition(to: mail, at: start.addingTimeInterval(30))
    await tracker.stop(at: start.addingTimeInterval(50))

    let intervals = await store.intervals
    #expect(intervals.map(\.application) == [safari, mail])
    #expect(intervals.map(\.duration) == [30, 20])
    #expect(intervals[0].end == intervals[1].start)
  }

  @Test(
    "idle, sleep, lock, and inactive session time is never attributed",
    arguments: [
      ActivityPauseReason.idle,
      .sleep,
      .locked,
      .inactiveSession,
    ]
  )
  func pauseReasonsExcludeTime(reason: ActivityPauseReason) async {
    let store = ActivityStoreSpy()
    let tracker = ApplicationActivityTracker(store: store)

    await tracker.transition(to: safari, at: start)
    await tracker.pause(reason: reason, at: start.addingTimeInterval(10))
    await tracker.resume(
      reason: reason,
      with: safari,
      at: start.addingTimeInterval(100)
    )
    await tracker.stop(at: start.addingTimeInterval(120))

    let intervals = await store.intervals
    #expect(intervals.map(\.duration) == [10, 20])
  }

  @Test("daily totals group by application identity")
  func dailyTotalsGroupByApplication() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
    let store = ActivityStoreSpy()
    let tracker = ApplicationActivityTracker(store: store, calendar: calendar)

    await tracker.transition(to: safari, at: start)
    await tracker.transition(to: mail, at: start.addingTimeInterval(20))
    await tracker.transition(to: safari, at: start.addingTimeInterval(35))
    await tracker.stop(at: start.addingTimeInterval(65))

    let totals = await tracker.dailyTotals(for: start)

    #expect(
      totals == [
        DailyApplicationTotal(application: safari, duration: 50),
        DailyApplicationTotal(application: mail, duration: 15),
      ])
  }

  @Test("daily totals include the current active interval")
  func dailyTotalsIncludeCurrentInterval() async {
    let store = ActivityStoreSpy()
    let through = start.addingTimeInterval(45)
    let tracker = ApplicationActivityTracker(
      store: store,
      now: { through }
    )

    await tracker.transition(to: safari, at: start)

    #expect(
      await tracker.dailyTotals(for: start) == [
        DailyApplicationTotal(application: safari, duration: 45)
      ]
    )
  }

  @Test("daily intervals include the current active interval")
  func dailyIntervalsIncludeCurrentInterval() async {
    let store = ActivityStoreSpy()
    let through = start.addingTimeInterval(45)
    let tracker = ApplicationActivityTracker(
      store: store,
      now: { through }
    )

    await tracker.transition(to: safari, at: start)

    #expect(
      await tracker.dailyIntervals(for: start) == [
        ApplicationActivityInterval(
          application: safari,
          start: start,
          end: through
        )
      ]
    )
  }

  @Test("one local store persists activity, fingerprints, candidates, and receipts")
  func unifiedStorePersistsStructuredRecords() async {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let candidate = MeetingCandidate(
      id: "candidate",
      title: "Planning",
      person: "Mona",
      start: start,
      sourceFingerprint: "fingerprint"
    )
    var store: ZoidLocalStore? = ZoidLocalStore(fileURL: fileURL)
    await store?.append(
      ApplicationActivityInterval(
        application: safari,
        start: start,
        end: start.addingTimeInterval(20)
      )
    )
    await store?.insert("fingerprint")
    await store?.record(candidate: candidate)
    await store?.record(
      receipt: SchedulingReceipt(
        eventCreated: true,
        reminderCreated: true
      ),
      for: candidate
    )

    store = nil
    let reopened = ZoidLocalStore(fileURL: fileURL)

    #expect(await reopened.contains("fingerprint"))
    #expect(
      await reopened.intervals(
        from: start.addingTimeInterval(-1),
        to: start.addingTimeInterval(30)
      ).count == 1
    )
    #expect(await reopened.recordedCandidateCount == 1)
    #expect(await reopened.recordedReceiptCount == 1)
  }
}

private actor ActivityStoreSpy: ApplicationActivityStoring {
  private(set) var intervals: [ApplicationActivityInterval] = []

  func append(_ interval: ApplicationActivityInterval) {
    intervals.append(interval)
  }

  func intervals(from start: Date, to end: Date) -> [ApplicationActivityInterval] {
    intervals.filter { $0.end > start && $0.start < end }
  }
}
