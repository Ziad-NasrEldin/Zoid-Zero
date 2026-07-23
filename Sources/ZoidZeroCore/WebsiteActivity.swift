import Foundation

public struct WebsiteIdentity: Codable, Equatable, Hashable, Sendable {
  public let browser: ApplicationIdentity
  public let domain: String

  public init(browser: ApplicationIdentity, domain: String) {
    self.browser = browser
    self.domain = domain
  }
}

public struct WebsiteActivityInterval: Codable, Equatable, Sendable {
  public let website: WebsiteIdentity
  public let start: Date
  public let end: Date

  public var duration: TimeInterval {
    max(0, end.timeIntervalSince(start))
  }

  public init(website: WebsiteIdentity, start: Date, end: Date) {
    self.website = website
    self.start = start
    self.end = end
  }
}

public protocol WebsiteActivityStoring: Sendable {
  func append(_ interval: WebsiteActivityInterval) async
  func websiteIntervals(from start: Date, to end: Date) async
    -> [WebsiteActivityInterval]
}

public enum RegistrableDomain {
  private static let compoundPublicSuffixes: Set<String> = [
    "ac.uk", "co.in", "co.jp", "co.nz", "co.uk", "com.ar", "com.au",
    "com.br", "com.cn", "com.eg", "com.hk", "com.mx", "com.sa", "com.sg",
    "com.tr", "com.tw", "edu.au", "edu.eg", "gov.au", "gov.uk", "gov.za",
    "net.au", "net.cn", "net.nz", "net.uk", "org.au", "org.cn", "org.nz",
    "org.uk",
  ]

  private static let privatePublicSuffixes: Set<String> = [
    "github.io"
  ]

  public static func normalized(from address: String) -> String? {
    guard let components = URLComponents(string: address),
      let scheme = components.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      var host = components.host?.lowercased(),
      !host.isEmpty
    else {
      return nil
    }
    while host.hasSuffix(".") {
      host.removeLast()
    }
    guard !host.isEmpty else { return nil }
    if host == "localhost" || isIPAddress(host) {
      return host
    }

    let labels = host.split(separator: ".").map(String.init)
    guard labels.count >= 2 else { return host }
    let suffixLength = longestSuffixLength(in: labels)
    guard labels.count > suffixLength else { return host }
    return labels.suffix(suffixLength + 1).joined(separator: ".")
  }

  private static func longestSuffixLength(in labels: [String]) -> Int {
    let candidates = compoundPublicSuffixes.union(privatePublicSuffixes)
    var result = 1
    for length in 2...min(3, labels.count) {
      let suffix = labels.suffix(length).joined(separator: ".")
      if candidates.contains(suffix) {
        result = length
      }
    }
    return result
  }

  private static func isIPAddress(_ host: String) -> Bool {
    if host.contains(":") {
      return host.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
    }
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return false }
    return parts.allSatisfy { part in
      guard let value = Int(part), value >= 0, value <= 255 else { return false }
      return String(value) == part || part == "0"
    }
  }
}

public struct TrackingSessionValidator: Sendable {
  public let maximumAge: TimeInterval

  public init(maximumAge: TimeInterval) {
    self.maximumAge = maximumAge
  }

  public func accepts(markerDate: Date?, eventDate: Date) -> Bool {
    guard let markerDate else { return false }
    let age = eventDate.timeIntervalSince(markerDate)
    return age >= 0 && age <= maximumAge
  }
}
