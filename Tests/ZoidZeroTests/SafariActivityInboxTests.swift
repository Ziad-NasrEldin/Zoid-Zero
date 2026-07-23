import Foundation
import Testing

@testable import ZoidZeroInfrastructure

@Suite("Safari activity inbox")
struct SafariActivityInboxTests {
  private let start = Date(timeIntervalSince1970: 1_753_200_000)

  @Test("tracking session marker follows app lifecycle")
  func trackingSessionMarkerFollowsLifecycle() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let inbox = SafariActivityInbox(rootURL: root)

    try await inbox.startSession(at: start)
    #expect(try await inbox.markerDate() == start)

    let refreshed = start.addingTimeInterval(10)
    try await inbox.refreshSession(at: refreshed)
    #expect(try await inbox.markerDate() == refreshed)

    try await inbox.endSession()
    #expect(try await inbox.markerDate() == nil)
  }

  @Test("events are consumed once in timestamp order")
  func eventsAreConsumedOnce() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let inbox = SafariActivityInbox(rootURL: root)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    try eventData(domain: "youtube.com", milliseconds: 20)
      .write(to: root.appendingPathComponent("event-20-b.json"), options: .atomic)
    try eventData(domain: "github.com", milliseconds: 10)
      .write(to: root.appendingPathComponent("event-10-a.json"), options: .atomic)

    let events = try await inbox.consumeEvents()

    #expect(events.map(\.domain) == ["github.com", "youtube.com"])
    #expect(try await inbox.consumeEvents().isEmpty)
  }

  @Test("malformed events are discarded without stopping later events")
  func malformedEventsAreDiscarded() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let inbox = SafariActivityInbox(rootURL: root)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    try Data("private invalid data".utf8)
      .write(to: root.appendingPathComponent("event-10-a.json"), options: .atomic)
    try eventData(domain: "github.com", milliseconds: 20)
      .write(to: root.appendingPathComponent("event-20-b.json"), options: .atomic)

    #expect(try await inbox.consumeEvents().map(\.domain) == ["github.com"])
    #expect(try await inbox.consumeEvents().isEmpty)
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  private func eventData(domain: String, milliseconds: Int64) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: [
        "kind": "activeDomain",
        "domain": domain,
        "timestampMilliseconds": milliseconds,
      ],
      options: [.sortedKeys]
    )
  }
}
