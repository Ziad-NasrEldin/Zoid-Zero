import Foundation
import ZoidZeroCore

public actor WebsiteActivityTracker {
  private let store: any WebsiteActivityStoring
  private let calendar: Calendar
  private let now: @Sendable () -> Date
  private var active: (website: WebsiteIdentity, start: Date)?

  public init(
    store: any WebsiteActivityStoring,
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.store = store
    self.calendar = calendar
    self.now = now
  }

  public func transition(
    to domain: String,
    browser: ApplicationIdentity,
    at date: Date
  ) async {
    let website = WebsiteIdentity(browser: browser, domain: domain)
    guard active?.website != website else { return }
    await finishActive(at: date)
    active = (website, date)
  }

  public func pause(at date: Date) async {
    await finishActive(at: date)
  }

  public func stop(at date: Date) async {
    await finishActive(at: date)
  }

  public func dailyIntervals(for date: Date) async -> [WebsiteActivityInterval] {
    let dayStart = calendar.startOfDay(for: date)
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
      return []
    }
    var result = await store.websiteIntervals(from: dayStart, to: dayEnd)
      .compactMap { interval -> WebsiteActivityInterval? in
        let clippedStart = max(interval.start, dayStart)
        let clippedEnd = min(interval.end, dayEnd)
        guard clippedEnd > clippedStart else { return nil }
        return WebsiteActivityInterval(
          website: interval.website,
          start: clippedStart,
          end: clippedEnd
        )
      }
    if let active {
      let clippedStart = max(active.start, dayStart)
      let clippedEnd = min(now(), dayEnd)
      if clippedEnd > clippedStart {
        result.append(
          WebsiteActivityInterval(
            website: active.website,
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
      WebsiteActivityInterval(
        website: active.website,
        start: active.start,
        end: date
      )
    )
  }
}
