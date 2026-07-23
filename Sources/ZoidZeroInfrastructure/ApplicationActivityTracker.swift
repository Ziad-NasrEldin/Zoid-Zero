import Foundation
import ZoidZeroCore

public actor ApplicationActivityTracker: ApplicationActivityTracking {
  private let store: any ApplicationActivityStoring
  private let calendar: Calendar
  private let now: @Sendable () -> Date
  private var active: (application: ApplicationIdentity, start: Date)?
  private var pauseReasons: Set<ActivityPauseReason> = []

  public init(
    store: any ApplicationActivityStoring,
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.store = store
    self.calendar = calendar
    self.now = now
  }

  public func transition(to application: ApplicationIdentity, at date: Date) async {
    guard pauseReasons.isEmpty else { return }
    if active?.application == application { return }
    await finishActive(at: date)
    active = (application, date)
  }

  public func pause(reason: ActivityPauseReason, at date: Date) async {
    if pauseReasons.isEmpty {
      await finishActive(at: date)
    }
    pauseReasons.insert(reason)
  }

  public func resume(
    reason: ActivityPauseReason,
    with application: ApplicationIdentity,
    at date: Date
  ) {
    pauseReasons.remove(reason)
    guard pauseReasons.isEmpty, active == nil else { return }
    active = (application, date)
  }

  public func stop(at date: Date) async {
    await finishActive(at: date)
    pauseReasons = [.inactiveSession]
  }

  public func dailyTotals(for date: Date) async -> [DailyApplicationTotal] {
    let intervals = await dailyIntervals(for: date)
    var durations: [ApplicationIdentity: TimeInterval] = [:]
    for interval in intervals {
      durations[interval.application, default: 0] += interval.duration
    }
    return
      durations
      .map(DailyApplicationTotal.init)
      .sorted {
        if $0.duration == $1.duration {
          return $0.application.displayName < $1.application.displayName
        }
        return $0.duration > $1.duration
      }
  }

  public func dailyIntervals(for date: Date) async -> [ApplicationActivityInterval] {
    let dayStart = calendar.startOfDay(for: date)
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
      return []
    }
    var result: [ApplicationActivityInterval] = []
    for interval in await store.intervals(from: dayStart, to: dayEnd) {
      let clippedStart = max(interval.start, dayStart)
      let clippedEnd = min(interval.end, dayEnd)
      guard clippedEnd > clippedStart else { continue }
      result.append(
        ApplicationActivityInterval(
          application: interval.application,
          start: clippedStart,
          end: clippedEnd
        )
      )
    }
    if let active {
      let clippedStart = max(active.start, dayStart)
      let clippedEnd = min(now(), dayEnd)
      if clippedEnd > clippedStart {
        result.append(
          ApplicationActivityInterval(
            application: active.application,
            start: clippedStart,
            end: clippedEnd
          )
        )
      }
    }
    return result.sorted { $0.start < $1.start }
  }

  private func finishActive(at date: Date) async {
    guard let active else { return }
    self.active = nil
    guard date > active.start else { return }
    await store.append(
      ApplicationActivityInterval(
        application: active.application,
        start: active.start,
        end: date
      )
    )
  }
}
