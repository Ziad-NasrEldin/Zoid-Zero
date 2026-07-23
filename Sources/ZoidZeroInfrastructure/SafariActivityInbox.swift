import Foundation

public struct SafariActivityEvent: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case activeDomain
    case domainUnavailable
  }

  public let kind: Kind
  public let domain: String?
  public let timestampMilliseconds: Int64

  public var date: Date {
    Date(timeIntervalSince1970: TimeInterval(timestampMilliseconds) / 1_000)
  }

  public init(
    kind: Kind,
    domain: String?,
    timestampMilliseconds: Int64
  ) {
    self.kind = kind
    self.domain = domain
    self.timestampMilliseconds = timestampMilliseconds
  }
}

public actor SafariActivityInbox {
  public static let appGroupIdentifier =
    "377QC32T9T.group.com.ziadnasreldin.zoidzero"

  private struct SessionMarker: Codable {
    let timestampMilliseconds: Int64

    var date: Date {
      Date(timeIntervalSince1970: TimeInterval(timestampMilliseconds) / 1_000)
    }
  }

  private let rootURL: URL
  private let fileManager: FileManager

  public init(rootURL: URL, fileManager: FileManager = .default) {
    self.rootURL = rootURL
    self.fileManager = fileManager
  }

  public static func sharedRootURL(
    fileManager: FileManager = .default
  ) -> URL? {
    fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    )?.appendingPathComponent("SafariActivity", isDirectory: true)
  }

  public func startSession(at date: Date) throws {
    try writeMarker(at: date)
  }

  public func refreshSession(at date: Date) throws {
    try writeMarker(at: date)
  }

  public func endSession() throws {
    let markerURL = rootURL.appendingPathComponent("tracking-session.json")
    guard fileManager.fileExists(atPath: markerURL.path) else { return }
    try fileManager.removeItem(at: markerURL)
  }

  public func markerDate() throws -> Date? {
    let markerURL = rootURL.appendingPathComponent("tracking-session.json")
    guard fileManager.fileExists(atPath: markerURL.path) else { return nil }
    return try JSONDecoder().decode(
      SessionMarker.self,
      from: Data(contentsOf: markerURL)
    ).date
  }

  public func consumeEvents() throws -> [SafariActivityEvent] {
    guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
    let urls = try fileManager.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: nil
    ).filter {
      $0.lastPathComponent.hasPrefix("event-")
        && $0.pathExtension == "json"
    }
    var events: [SafariActivityEvent] = []
    for url in urls {
      defer { try? fileManager.removeItem(at: url) }
      guard
        let event = try? JSONDecoder().decode(
          SafariActivityEvent.self,
          from: Data(contentsOf: url)
        )
      else {
        continue
      }
      events.append(event)
    }
    return events.sorted {
      if $0.timestampMilliseconds == $1.timestampMilliseconds {
        return ($0.domain ?? "") < ($1.domain ?? "")
      }
      return $0.timestampMilliseconds < $1.timestampMilliseconds
    }
  }

  private func writeMarker(at date: Date) throws {
    try fileManager.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true
    )
    let marker = SessionMarker(
      timestampMilliseconds: Int64(date.timeIntervalSince1970 * 1_000)
    )
    try JSONEncoder().encode(marker).write(
      to: rootURL.appendingPathComponent("tracking-session.json"),
      options: .atomic
    )
  }
}
