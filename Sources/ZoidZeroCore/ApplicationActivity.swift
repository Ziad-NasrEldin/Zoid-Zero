import Foundation

public struct ApplicationIdentity: Codable, Equatable, Hashable, Sendable {
  public let bundleIdentifier: String
  public let displayName: String

  public init(bundleIdentifier: String, displayName: String) {
    self.bundleIdentifier = bundleIdentifier
    self.displayName = displayName
  }
}

public struct ApplicationActivityInterval: Codable, Equatable, Sendable {
  public let application: ApplicationIdentity
  public let start: Date
  public let end: Date

  public var duration: TimeInterval {
    max(0, end.timeIntervalSince(start))
  }

  public init(application: ApplicationIdentity, start: Date, end: Date) {
    self.application = application
    self.start = start
    self.end = end
  }
}

public struct DailyApplicationTotal: Equatable, Sendable {
  public let application: ApplicationIdentity
  public let duration: TimeInterval

  public init(application: ApplicationIdentity, duration: TimeInterval) {
    self.application = application
    self.duration = duration
  }
}

public enum ActivityPauseReason: String, Codable, Equatable, Sendable {
  case idle
  case sleep
  case locked
  case inactiveSession
}

public protocol ApplicationActivityStoring: Sendable {
  func append(_ interval: ApplicationActivityInterval) async
  func intervals(from start: Date, to end: Date) async -> [ApplicationActivityInterval]
}

public protocol ApplicationActivityTracking: Sendable {
  func transition(to application: ApplicationIdentity, at date: Date) async
  func pause(reason: ActivityPauseReason, at date: Date) async
  func resume(
    reason: ActivityPauseReason,
    with application: ApplicationIdentity,
    at date: Date
  ) async
  func dailyIntervals(for date: Date) async -> [ApplicationActivityInterval]
  func dailyTotals(for date: Date) async -> [DailyApplicationTotal]
  func stop(at date: Date) async
}
