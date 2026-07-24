import Foundation

public enum ActivityCategory: String, Codable, CaseIterable, Equatable, Sendable {
  case work
  case communication
  case social
  case gaming
  case media
  case utilities
  case browser
  case uncategorized

  public var displayName: String {
    switch self {
    case .work: "Work"
    case .communication: "Communication"
    case .social: "Social"
    case .gaming: "Gaming"
    case .media: "Media"
    case .utilities: "Utilities"
    case .browser: "Browser"
    case .uncategorized: "Uncategorized"
    }
  }
}

public enum ActivitySubject: Codable, Equatable, Hashable, Sendable {
  case application(bundleIdentifier: String)
  case website(domain: String)

  public var stableIdentifier: String {
    switch self {
    case .application(let bundleIdentifier):
      "app:\(bundleIdentifier)"
    case .website(let domain):
      "web:\(domain)"
    }
  }
}

public protocol CategoryAssignmentStoring: Sendable {
  func setCategory(_ category: ActivityCategory, for subject: ActivitySubject) async
  func resetCategory(for subject: ActivitySubject) async
  func userCategoryAssignments() async -> [ActivitySubject: ActivityCategory]
}

public protocol AutomaticCategoryStoring: Sendable {
  func setAutomaticCategory(
    _ category: ActivityCategory,
    for subject: ActivitySubject
  ) async
  func automaticCategoryAssignments() async -> [ActivitySubject: ActivityCategory]
  func userCategoryAssignments() async -> [ActivitySubject: ActivityCategory]
  func observedActivityMetadata() async -> [ActivityMetadata]
}

public struct ActivityMetadata: Equatable, Hashable, Sendable {
  public let subject: ActivitySubject
  public let displayName: String

  public init(subject: ActivitySubject, displayName: String) {
    self.subject = subject
    self.displayName = displayName
  }
}

public enum CategoryAssignmentSource: String, Equatable, Sendable {
  case manual
  case automatic
  case builtIn
  case unknown
}

public struct CategoryResolution: Equatable, Sendable {
  public let category: ActivityCategory
  public let source: CategoryAssignmentSource

  public init(category: ActivityCategory, source: CategoryAssignmentSource) {
    self.category = category
    self.source = source
  }
}

public enum DefaultActivityCategories {
  public static let assignments: [ActivitySubject: ActivityCategory] = [
    .application(bundleIdentifier: "com.apple.Safari"): .browser,
    .application(bundleIdentifier: "com.google.Chrome"): .browser,
    .application(bundleIdentifier: "company.thebrowser.Browser"): .browser,
    .application(bundleIdentifier: "org.mozilla.firefox"): .browser,
    .application(bundleIdentifier: "com.apple.dt.Xcode"): .work,
    .application(bundleIdentifier: "com.apple.Terminal"): .work,
    .application(bundleIdentifier: "com.openai.chat"): .work,
    .application(bundleIdentifier: "com.tinyspeck.slackmacgap"): .communication,
    .application(bundleIdentifier: "net.whatsapp.WhatsApp"): .communication,
    .application(bundleIdentifier: "com.apple.mail"): .communication,
    .application(bundleIdentifier: "com.apple.MobileSMS"): .communication,
    .application(bundleIdentifier: "com.valvesoftware.steam"): .gaming,
    .application(bundleIdentifier: "com.spotify.client"): .media,
    .application(bundleIdentifier: "com.apple.Music"): .media,
    .application(bundleIdentifier: "com.apple.finder"): .utilities,
    .application(bundleIdentifier: "com.apple.systempreferences"): .utilities,
    .application(bundleIdentifier: "com.apple.systemsettings"): .utilities,
    .website(domain: "github.com"): .work,
    .website(domain: "notion.so"): .work,
    .website(domain: "figma.com"): .work,
    .website(domain: "linear.app"): .work,
    .website(domain: "slack.com"): .communication,
    .website(domain: "whatsapp.com"): .communication,
    .website(domain: "reddit.com"): .social,
    .website(domain: "x.com"): .social,
    .website(domain: "facebook.com"): .social,
    .website(domain: "instagram.com"): .social,
    .website(domain: "youtube.com"): .media,
    .website(domain: "netflix.com"): .media,
    .website(domain: "spotify.com"): .media,
  ]
}

public struct CategoryAssignmentResolver: Sendable {
  public let defaults: [ActivitySubject: ActivityCategory]
  public let automaticAssignments: [ActivitySubject: ActivityCategory]
  public let userAssignments: [ActivitySubject: ActivityCategory]

  public init(
    defaults: [ActivitySubject: ActivityCategory] = [:],
    automaticAssignments: [ActivitySubject: ActivityCategory] = [:],
    userAssignments: [ActivitySubject: ActivityCategory] = [:]
  ) {
    self.defaults = defaults
    self.automaticAssignments = automaticAssignments
    self.userAssignments = userAssignments
  }

  public func category(for subject: ActivitySubject) -> ActivityCategory {
    resolution(for: subject).category
  }

  public func resolution(for subject: ActivitySubject) -> CategoryResolution {
    if let category = userAssignments[subject] {
      return CategoryResolution(category: category, source: .manual)
    }
    if let category = automaticAssignments[subject] {
      return CategoryResolution(category: category, source: .automatic)
    }
    if let category = defaults[subject] {
      return CategoryResolution(category: category, source: .builtIn)
    }
    return CategoryResolution(category: .uncategorized, source: .unknown)
  }
}

public struct DeterministicActivityClassifier: Sendable {
  public init() {}

  public func classify(
    _ subject: ActivitySubject,
    displayName: String
  ) -> ActivityCategory? {
    if let exact = DefaultActivityCategories.assignments[subject] {
      return exact
    }

    switch subject {
    case .application(let bundleIdentifier):
      return classifyApplication(
        bundleIdentifier: bundleIdentifier.lowercased(),
        displayName: displayName.lowercased()
      )
    case .website(let domain):
      return classifyWebsite(domain.lowercased())
    }
  }

  private func classifyApplication(
    bundleIdentifier: String,
    displayName: String
  ) -> ActivityCategory? {
    let value = "\(bundleIdentifier) \(displayName)"
    let rules: [(ActivityCategory, [String])] = [
      (.communication, ["slack", "whatsapp", "telegram", "discord", "zoom", "teams"]),
      (.gaming, ["steam", "epicgames", "riotclient", "leagueoflegends"]),
      (.media, ["spotify", "vlc", "music", "podcasts"]),
      (.browser, ["safari", "chrome", "firefox", "browser", "arc"]),
      (.work, ["xcode", "vscode", "visual studio code", "jetbrains", "terminal", "iterm"]),
      (.utilities, ["finder", "systemsettings", "systempreferences", "activitymonitor"]),
    ]
    for (category, tokens) in rules where tokens.contains(where: value.contains) {
      return category
    }
    return nil
  }

  private func classifyWebsite(_ domain: String) -> ActivityCategory? {
    let exactOrSubdomain: [(ActivityCategory, [String])] = [
      (.work, ["github.com", "gitlab.com", "figma.com", "linear.app", "notion.so"]),
      (.communication, ["slack.com", "whatsapp.com", "discord.com", "zoom.us"]),
      (.social, ["reddit.com", "x.com", "facebook.com", "instagram.com", "linkedin.com"]),
      (.media, ["youtube.com", "netflix.com", "spotify.com", "twitch.tv"]),
      (.gaming, ["steampowered.com", "epicgames.com", "riotgames.com"]),
    ]
    for (category, domains) in exactOrSubdomain {
      if domains.contains(where: { domain == $0 || domain.hasSuffix(".\($0)") }) {
        return category
      }
    }
    return nil
  }
}

public struct DailyActivityContributor: Equatable, Identifiable, Sendable {
  public let subject: ActivitySubject
  public let displayName: String
  public let category: ActivityCategory
  public let categorySource: CategoryAssignmentSource
  public let duration: TimeInterval

  public var id: String {
    subject.stableIdentifier
  }

  public init(
    subject: ActivitySubject,
    displayName: String,
    category: ActivityCategory,
    categorySource: CategoryAssignmentSource = .unknown,
    duration: TimeInterval
  ) {
    self.subject = subject
    self.displayName = displayName
    self.category = category
    self.categorySource = categorySource
    self.duration = max(0, duration)
  }
}

public struct DailyCategoryTotal: Equatable, Identifiable, Sendable {
  public let category: ActivityCategory
  public let duration: TimeInterval

  public var id: ActivityCategory {
    category
  }

  public init(category: ActivityCategory, duration: TimeInterval) {
    self.category = category
    self.duration = max(0, duration)
  }
}

public struct DailyActivityReport: Equatable, Sendable {
  public let contributors: [DailyActivityContributor]
  public let categoryTotals: [DailyCategoryTotal]
  public let totalDuration: TimeInterval

  public init(contributors: [DailyActivityContributor]) {
    self.contributors = contributors.sorted {
      if $0.duration == $1.duration {
        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
          == .orderedAscending
      }
      return $0.duration > $1.duration
    }
    totalDuration = contributors.reduce(0) { $0 + $1.duration }
    let grouped = Dictionary(grouping: contributors, by: \.category)
    categoryTotals = ActivityCategory.allCases.compactMap { category in
      guard let values = grouped[category], !values.isEmpty else { return nil }
      return DailyCategoryTotal(
        category: category,
        duration: values.reduce(0) { $0 + $1.duration }
      )
    }
  }

  public func total(for category: ActivityCategory) -> DailyCategoryTotal? {
    categoryTotals.first { $0.category == category }
  }

  public func contributors(in category: ActivityCategory?) -> [DailyActivityContributor] {
    guard let category else { return contributors }
    return contributors.filter { $0.category == category }
  }
}

public enum ActivityIntervalReconciler {
  public static func reconcile(
    applications: [ApplicationActivityInterval],
    websites: [WebsiteActivityInterval],
    categories: CategoryAssignmentResolver
  ) -> [DailyActivityContributor] {
    struct Key: Hashable {
      let subject: ActivitySubject
      let displayName: String
      let category: ActivityCategory
    }

    var durations: [Key: TimeInterval] = [:]

    func add(
      subject: ActivitySubject,
      displayName: String,
      start: Date,
      end: Date
    ) {
      guard end > start else { return }
      let resolution = categories.resolution(for: subject)
      let key = Key(
        subject: subject,
        displayName: displayName,
        category: resolution.category
      )
      durations[key, default: 0] += end.timeIntervalSince(start)
    }

    for applicationInterval in applications {
      let applicationSubject = ActivitySubject.application(
        bundleIdentifier: applicationInterval.application.bundleIdentifier
      )
      let matchingWebsites =
        websites
        .filter {
          $0.website.browser.bundleIdentifier
            == applicationInterval.application.bundleIdentifier
            && $0.end > applicationInterval.start
            && $0.start < applicationInterval.end
        }
        .sorted {
          if $0.start == $1.start { return $0.end < $1.end }
          return $0.start < $1.start
        }

      var cursor = applicationInterval.start
      for websiteInterval in matchingWebsites {
        let websiteStart = max(cursor, max(websiteInterval.start, applicationInterval.start))
        let websiteEnd = min(websiteInterval.end, applicationInterval.end)
        if websiteStart > cursor {
          add(
            subject: applicationSubject,
            displayName: applicationInterval.application.displayName,
            start: cursor,
            end: websiteStart
          )
        }
        guard websiteEnd > websiteStart else { continue }
        let websiteSubject = ActivitySubject.website(
          domain: websiteInterval.website.domain
        )
        add(
          subject: websiteSubject,
          displayName: websiteInterval.website.domain,
          start: websiteStart,
          end: websiteEnd
        )
        cursor = websiteEnd
      }
      if cursor < applicationInterval.end {
        add(
          subject: applicationSubject,
          displayName: applicationInterval.application.displayName,
          start: cursor,
          end: applicationInterval.end
        )
      }
    }

    return durations.map {
      DailyActivityContributor(
        subject: $0.key.subject,
        displayName: $0.key.displayName,
        category: $0.key.category,
        categorySource: categories.resolution(for: $0.key.subject).source,
        duration: $0.value
      )
    }
  }
}
