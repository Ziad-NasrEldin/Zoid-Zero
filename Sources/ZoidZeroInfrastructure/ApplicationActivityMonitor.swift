import AppKit
import CoreGraphics
import Foundation
import ZoidZeroCore

@MainActor
public protocol ApplicationActivityControlling: AnyObject {
  func start()
  func stop() async
  func dailyIntervals(for date: Date) async -> [ApplicationActivityInterval]
  func dailyTotals(for date: Date) async -> [DailyApplicationTotal]
}

@MainActor
public final class ApplicationActivityMonitor: ApplicationActivityControlling {
  private let tracker: any ApplicationActivityTracking
  private let idleThreshold: TimeInterval
  private let idleDetector = UserInputIdleDetector()
  private var workspaceObservers: [NSObjectProtocol] = []
  private var distributedObservers: [NSObjectProtocol] = []
  private var idleTask: Task<Void, Never>?
  private var started = false

  public init(
    tracker: any ApplicationActivityTracking,
    idleThreshold: TimeInterval = 90
  ) {
    self.tracker = tracker
    self.idleThreshold = idleThreshold
  }

  public func start() {
    guard !started else { return }
    started = true
    registerWorkspaceObservers()
    registerSessionObservers()
    activateFrontmostApplication(at: Date())
    idleTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard let self, !Task.isCancelled else { return }
        await self.updateIdleState()
      }
    }
  }

  public func stop(at date: Date = Date()) async {
    guard started else { return }
    started = false
    idleTask?.cancel()
    idleTask = nil
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceObservers.forEach(workspaceCenter.removeObserver)
    workspaceObservers.removeAll()
    let distributedCenter = DistributedNotificationCenter.default()
    distributedObservers.forEach(distributedCenter.removeObserver)
    distributedObservers.removeAll()
    await tracker.stop(at: date)
  }

  public func stop() async {
    await stop(at: Date())
  }

  public func dailyTotals(for date: Date = Date()) async -> [DailyApplicationTotal] {
    await tracker.dailyTotals(for: date)
  }

  public func dailyIntervals(
    for date: Date = Date()
  ) async -> [ApplicationActivityInterval] {
    await tracker.dailyIntervals(for: date)
  }

  private func registerWorkspaceObservers() {
    let center = NSWorkspace.shared.notificationCenter
    observe(center, name: NSWorkspace.didActivateApplicationNotification) {
      [weak self] _ in
      Task { @MainActor in self?.activateFrontmostApplication(at: Date()) }
    }
    observe(center, name: NSWorkspace.willSleepNotification) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        await self.tracker.pause(reason: .sleep, at: Date())
      }
    }
    observe(center, name: NSWorkspace.didWakeNotification) { [weak self] _ in
      Task { @MainActor in self?.resume(reason: .sleep) }
    }
    observe(center, name: NSWorkspace.sessionDidResignActiveNotification) {
      [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        await self.tracker.pause(reason: .inactiveSession, at: Date())
      }
    }
    observe(center, name: NSWorkspace.sessionDidBecomeActiveNotification) {
      [weak self] _ in
      Task { @MainActor in self?.resume(reason: .inactiveSession) }
    }
  }

  private func registerSessionObservers() {
    let center = DistributedNotificationCenter.default()
    distributedObservers.append(
      center.addObserver(
        forName: .init("com.apple.screenIsLocked"),
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          await self.tracker.pause(reason: .locked, at: Date())
        }
      }
    )
    distributedObservers.append(
      center.addObserver(
        forName: .init("com.apple.screenIsUnlocked"),
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.resume(reason: .locked) }
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

  private func updateIdleState() async {
    let idle = idleDetector.idleDuration()
    if idle >= idleThreshold {
      await tracker.pause(
        reason: .idle,
        at: Date().addingTimeInterval(-idle)
      )
    } else {
      resume(reason: .idle)
    }
  }

  private func resume(reason: ActivityPauseReason) {
    guard let application = NSWorkspace.shared.frontmostApplication else { return }
    let identity = Self.identity(for: application)
    Task {
      await tracker.resume(reason: reason, with: identity, at: Date())
    }
  }

  private func activateFrontmostApplication(at date: Date) {
    guard let application = NSWorkspace.shared.frontmostApplication else { return }
    let identity = Self.identity(for: application)
    Task { await tracker.transition(to: identity, at: date) }
  }

  private static func identity(for application: NSRunningApplication) -> ApplicationIdentity {
    ApplicationIdentity(
      bundleIdentifier: application.bundleIdentifier
        ?? "pid.\(application.processIdentifier)",
      displayName: application.localizedName ?? "Unknown"
    )
  }
}
