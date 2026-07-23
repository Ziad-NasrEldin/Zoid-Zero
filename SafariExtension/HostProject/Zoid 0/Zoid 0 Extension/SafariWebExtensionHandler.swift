import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  private static let appGroupIdentifier = "group.com.ziadnasreldin.zoidzero"
  private static let maximumMarkerAgeMilliseconds: Int64 = 30_000

  func beginRequest(with context: NSExtensionContext) {
    let response = NSExtensionItem()
    response.userInfo = [SFExtensionMessageKey: ["accepted": accept(context)]]
    context.completeRequest(returningItems: [response], completionHandler: nil)
  }

  private func accept(_ context: NSExtensionContext) -> Bool {
    guard
      let request = context.inputItems.first as? NSExtensionItem,
      let message = request.userInfo?[SFExtensionMessageKey] as? [String: Any],
      let event = sanitizedEvent(from: message),
      let root = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
      )?.appendingPathComponent("SafariActivity", isDirectory: true),
      markerAllows(event: event, in: root)
    else {
      return false
    }

    do {
      try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
      )
      let data = try JSONSerialization.data(
        withJSONObject: event.dictionary,
        options: [.sortedKeys]
      )
      let eventURL = root.appendingPathComponent(
        "event-\(event.timestampMilliseconds)-\(UUID().uuidString).json"
      )
      try data.write(to: eventURL, options: .atomic)
      return true
    } catch {
      return false
    }
  }

  private func sanitizedEvent(from message: [String: Any]) -> Event? {
    guard
      let kind = message["kind"] as? String,
      let timestamp = integer(from: message["timestampMilliseconds"])
    else {
      return nil
    }
    switch kind {
    case "activeDomain":
      guard
        let domain = message["domain"] as? String,
        isSafe(domain: domain)
      else {
        return nil
      }
      return Event(
        kind: kind,
        domain: domain,
        timestampMilliseconds: timestamp
      )
    case "domainUnavailable":
      return Event(
        kind: kind,
        domain: nil,
        timestampMilliseconds: timestamp
      )
    default:
      return nil
    }
  }

  private func markerAllows(event: Event, in root: URL) -> Bool {
    let markerURL = root.appendingPathComponent("tracking-session.json")
    guard
      let data = try? Data(contentsOf: markerURL),
      let object = try? JSONSerialization.jsonObject(with: data)
        as? [String: Any],
      let marker = integer(from: object["timestampMilliseconds"])
    else {
      return false
    }
    let age = event.timestampMilliseconds - marker
    return age >= 0 && age <= Self.maximumMarkerAgeMilliseconds
  }

  private func integer(from value: Any?) -> Int64? {
    if let value = value as? Int64 {
      return value
    }
    if let value = value as? NSNumber {
      return value.int64Value
    }
    return nil
  }

  private func isSafe(domain: String) -> Bool {
    guard !domain.isEmpty, domain.count <= 253 else { return false }
    return domain.unicodeScalars.allSatisfy {
      CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-:")
        .contains($0)
    }
  }
}

private struct Event {
  let kind: String
  let domain: String?
  let timestampMilliseconds: Int64

  var dictionary: [String: Any] {
    var value: [String: Any] = [
      "kind": kind,
      "timestampMilliseconds": timestampMilliseconds,
    ]
    if let domain {
      value["domain"] = domain
    }
    return value
  }
}
