import Foundation
import Testing

@testable import ZoidZeroCore
@testable import ZoidZeroInfrastructure

@Suite("Safari website activity controller")
@MainActor
struct SafariWebsiteActivityControllerTests {
  private let start = Date(timeIntervalSince1970: 1_753_200_000)

  @Test("foreground Safari events become website intervals")
  func foregroundSafariEventsBecomeIntervals() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = ControllerClock(start)
    let store = ControllerWebsiteStore()
    let tracker = WebsiteActivityTracker(store: store, now: clock.now)
    let inbox = SafariActivityInbox(rootURL: root)
    let controller = SafariWebsiteActivityController(
      inbox: inbox,
      tracker: tracker,
      frontmostBundleIdentifier: { "com.apple.Safari" },
      idleDuration: { 0 },
      now: clock.now
    )
    try await controller.start(automaticallyPoll: false)
    try writeEvent(
      root: root,
      kind: "activeDomain",
      domain: "github.com",
      date: start
    )

    await controller.pollOnce()
    clock.value = start.addingTimeInterval(20)
    await controller.stop()

    #expect(await store.values.map(\.website.domain) == ["github.com"])
    #expect(await store.values.map(\.duration) == [20])
    #expect(try await inbox.markerDate() == nil)
  }

  @Test("unavailable domains close website attribution")
  func unavailableDomainClosesAttribution() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = ControllerClock(start)
    let store = ControllerWebsiteStore()
    let tracker = WebsiteActivityTracker(store: store, now: clock.now)
    let controller = SafariWebsiteActivityController(
      inbox: SafariActivityInbox(rootURL: root),
      tracker: tracker,
      frontmostBundleIdentifier: { "com.apple.Safari" },
      idleDuration: { 0 },
      now: clock.now
    )
    try await controller.start(automaticallyPoll: false)
    try writeEvent(
      root: root,
      kind: "activeDomain",
      domain: "github.com",
      date: start
    )
    await controller.pollOnce()
    clock.value = start.addingTimeInterval(12)
    try writeEvent(
      root: root,
      kind: "domainUnavailable",
      domain: nil,
      date: clock.value
    )

    await controller.pollOnce()

    #expect(await store.values.map(\.duration) == [12])
  }

  @Test("events are ignored while Safari is not foreground")
  func backgroundSafariEventsAreIgnored() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ControllerWebsiteStore()
    let tracker = WebsiteActivityTracker(store: store)
    let controller = SafariWebsiteActivityController(
      inbox: SafariActivityInbox(rootURL: root),
      tracker: tracker,
      frontmostBundleIdentifier: { "com.apple.dt.Xcode" },
      idleDuration: { 0 }
    )
    try await controller.start(automaticallyPoll: false)
    try writeEvent(
      root: root,
      kind: "activeDomain",
      domain: "github.com",
      date: start
    )

    await controller.pollOnce()
    await controller.stop()

    #expect(await store.values.isEmpty)
    #expect(controller.state == .on)
  }

  @Test("idle time closes domain attribution at the last user input")
  func idleTimeIsNotStoredAsWebsiteActivity() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = ControllerClock(start)
    let idle = ControllerClock(Date(timeIntervalSince1970: 0))
    let store = ControllerWebsiteStore()
    let controller = SafariWebsiteActivityController(
      inbox: SafariActivityInbox(rootURL: root),
      tracker: WebsiteActivityTracker(store: store, now: clock.now),
      frontmostBundleIdentifier: { "com.apple.Safari" },
      idleDuration: { idle.value.timeIntervalSince1970 },
      now: clock.now
    )
    try await controller.start(automaticallyPoll: false)
    try writeEvent(
      root: root,
      kind: "activeDomain",
      domain: "github.com",
      date: start
    )
    await controller.pollOnce()

    clock.value = start.addingTimeInterval(120)
    idle.value = Date(timeIntervalSince1970: 90)
    await controller.pollOnce()

    #expect(await store.values.map(\.duration) == [30])
  }

  @Test(
    "extension availability resolves to an honest visible state",
    arguments: [
      (Optional<Bool>.none, SafariWebsiteTrackingState.unavailable),
      (.some(false), .extensionDisabled),
      (.some(true), .permissionNeeded),
    ]
  )
  func extensionAvailabilityIsHonest(
    enabled: Bool?,
    expected: SafariWebsiteTrackingState
  ) {
    #expect(
      SafariWebsiteStateResolver.resolve(
        extensionEnabled: enabled,
        controllerState: .permissionNeeded
      ) == expected
    )
    if enabled == true {
      #expect(
        SafariWebsiteStateResolver.resolve(
          extensionEnabled: enabled,
          controllerState: .on
        ) == .on
      )
    }
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  private func writeEvent(
    root: URL,
    kind: String,
    domain: String?,
    date: Date
  ) throws {
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let milliseconds = Int64(date.timeIntervalSince1970 * 1_000)
    var object: [String: Any] = [
      "kind": kind,
      "timestampMilliseconds": milliseconds,
    ]
    object["domain"] = domain
    let data = try JSONSerialization.data(withJSONObject: object)
    try data.write(
      to: root.appendingPathComponent("event-\(milliseconds)-test.json"),
      options: .atomic
    )
  }
}

private final class ControllerClock: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: Date

  init(_ value: Date) {
    storedValue = value
  }

  var value: Date {
    get {
      lock.withLock { storedValue }
    }
    set {
      lock.withLock { storedValue = newValue }
    }
  }

  func now() -> Date {
    value
  }
}

private actor ControllerWebsiteStore: WebsiteActivityStoring {
  private(set) var values: [WebsiteActivityInterval] = []

  func append(_ interval: WebsiteActivityInterval) {
    values.append(interval)
  }

  func websiteIntervals(
    from start: Date,
    to end: Date
  ) -> [WebsiteActivityInterval] {
    values.filter { $0.end > start && $0.start < end }
  }
}
