import AppKit
import Foundation
import ZoidZeroCore

public enum SafariWebsiteTrackingState: String, Equatable, Sendable {
  case on
  case permissionNeeded
  case extensionDisabled
  case unavailable
}

@MainActor
public protocol SafariWebsiteActivityControlling: AnyObject {
  var state: SafariWebsiteTrackingState { get }
  func start() async throws
  func stop() async
  func dailyIntervals(for date: Date) async -> [WebsiteActivityInterval]
}

@MainActor
public final class SafariWebsiteActivityController:
  SafariWebsiteActivityControlling
{
  public private(set) var state: SafariWebsiteTrackingState = .permissionNeeded

  private let inbox: SafariActivityInbox
  private let tracker: WebsiteActivityTracker
  private let frontmostBundleIdentifier: () -> String?
  private let idleDuration: () -> TimeInterval
  private let now: @Sendable () -> Date
  private var pollingTask: Task<Void, Never>?
  private var lastEventDate: Date?
  private var lastKnownDomain: String?
  private var pauseReasons: Set<ActivityPauseReason> = []
  private var workspaceObservers: [NSObjectProtocol] = []
  private var distributedObservers: [NSObjectProtocol] = []
  private var started = false

  public init(
    inbox: SafariActivityInbox,
    tracker: WebsiteActivityTracker,
    frontmostBundleIdentifier: @escaping () -> String?,
    idleDuration: (() -> TimeInterval)? = nil,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.inbox = inbox
    self.tracker = tracker
    self.frontmostBundleIdentifier = frontmostBundleIdentifier
    self.idleDuration =
      idleDuration ?? {
        UserInputIdleDetector().idleDuration()
      }
    self.now = now
  }

  public func start() async throws {
    try await start(automaticallyPoll: true)
  }

  public func start(automaticallyPoll: Bool) async throws {
    guard !started else { return }
    started = true
    registerPauseObservers()
    try await inbox.startSession(at: now())
    guard automaticallyPoll else { return }
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.pollOnce()
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }

  public func pollOnce() async {
    guard started else { return }
    let pollDate = now()
    do {
      try await inbox.refreshSession(at: pollDate)
      let events = try await inbox.consumeEvents()
      var acceptedEvents: [SafariActivityEvent] = []
      for event in events {
        guard event.date <= pollDate,
          lastEventDate == nil || event.date > lastEventDate!
        else {
          continue
        }
        lastEventDate = event.date
        acceptedEvents.append(event)
        lastKnownDomain = event.kind == .activeDomain ? event.domain : nil
      }
      let idle = idleDuration()
      guard pauseReasons.isEmpty, idle < 90 else {
        let pauseDate = idle >= 90
          ? pollDate.addingTimeInterval(-idle)
          : pollDate
        await tracker.pause(at: pauseDate)
        return
      }
      guard frontmostBundleIdentifier() == "com.apple.Safari" else {
        await tracker.pause(at: pollDate)
        return
      }
      for event in acceptedEvents {
        switch event.kind {
        case .activeDomain:
          guard let domain = event.domain else { continue }
          await tracker.transition(
            to: domain,
            browser: ApplicationIdentity(
              bundleIdentifier: "com.apple.Safari",
              displayName: "Safari"
            ),
            at: event.date
          )
          state = .on
        case .domainUnavailable:
          await tracker.pause(at: event.date)
          state = .permissionNeeded
        }
      }
      if acceptedEvents.isEmpty, let lastKnownDomain {
        await tracker.transition(
          to: lastKnownDomain,
          browser: ApplicationIdentity(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari"
          ),
          at: pollDate
        )
        state = .on
      }
    } catch {
      state = .unavailable
      await tracker.pause(at: pollDate)
    }
  }

  public func dailyIntervals(for date: Date) async -> [WebsiteActivityInterval] {
    await tracker.dailyIntervals(for: date)
  }

  public func stop() async {
    guard started else { return }
    started = false
    pollingTask?.cancel()
    pollingTask = nil
    removePauseObservers()
    await tracker.stop(at: now())
    try? await inbox.endSession()
  }

  private func registerPauseObservers() {
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    observe(workspaceCenter, name: NSWorkspace.willSleepNotification) {
      [weak self] _ in
      Task { @MainActor in await self?.pause(for: .sleep) }
    }
    observe(workspaceCenter, name: NSWorkspace.didWakeNotification) {
      [weak self] _ in
      Task { @MainActor in self?.resume(from: .sleep) }
    }
    observe(workspaceCenter, name: NSWorkspace.sessionDidResignActiveNotification) {
      [weak self] _ in
      Task { @MainActor in await self?.pause(for: .inactiveSession) }
    }
    observe(workspaceCenter, name: NSWorkspace.sessionDidBecomeActiveNotification) {
      [weak self] _ in
      Task { @MainActor in self?.resume(from: .inactiveSession) }
    }

    let distributedCenter = DistributedNotificationCenter.default()
    distributedObservers.append(
      distributedCenter.addObserver(
        forName: .init("com.apple.screenIsLocked"),
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in await self?.pause(for: .locked) }
      }
    )
    distributedObservers.append(
      distributedCenter.addObserver(
        forName: .init("com.apple.screenIsUnlocked"),
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.resume(from: .locked) }
      }
    )
  }

  private func observe(
    _ center: NotificationCenter,
    name: Notification.Name,
    handler: @escaping @Sendable (Notification) -> Void
  ) {
    workspaceObservers.append(
      center.addObserver(forName: name, object: nil, queue: .main, using: handler)
    )
  }

  private func pause(for reason: ActivityPauseReason) async {
    pauseReasons.insert(reason)
    await tracker.pause(at: now())
  }

  private func resume(from reason: ActivityPauseReason) {
    pauseReasons.remove(reason)
  }

  private func removePauseObservers() {
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceObservers.forEach(workspaceCenter.removeObserver)
    workspaceObservers.removeAll()
    let distributedCenter = DistributedNotificationCenter.default()
    distributedObservers.forEach(distributedCenter.removeObserver)
    distributedObservers.removeAll()
  }
}
