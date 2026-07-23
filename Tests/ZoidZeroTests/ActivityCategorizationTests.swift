import Foundation
import Testing

@testable import ZoidZeroCore

@Suite("Activity categorization")
struct ActivityCategorizationTests {
  @Test("initial categories remain stable and complete")
  func initialCategoriesAreStable() {
    #expect(
      ActivityCategory.allCases == [
        .work,
        .communication,
        .social,
        .gaming,
        .media,
        .utilities,
        .browser,
        .uncategorized,
      ])
  }

  @Test("assignments use stable identifiers")
  func subjectsUseStableIdentifiers() {
    #expect(
      ActivitySubject.application(bundleIdentifier: "com.apple.Safari")
        != .application(bundleIdentifier: "Safari")
    )
    #expect(
      ActivitySubject.website(domain: "youtube.com")
        != .website(domain: "YouTube")
    )
  }

  @Test("user assignments override defaults")
  func userAssignmentsOverrideDefaults() {
    let subject = ActivitySubject.website(domain: "twitch.tv")
    let resolver = CategoryAssignmentResolver(
      defaults: [subject: .media],
      userAssignments: [subject: .gaming]
    )

    #expect(resolver.category(for: subject) == .gaming)
  }

  @Test("unknown subjects remain uncategorized")
  func unknownSubjectsRemainUncategorized() {
    let resolver = CategoryAssignmentResolver()

    #expect(
      resolver.category(
        for: .application(bundleIdentifier: "com.example.unknown")
      ) == .uncategorized
    )
  }

  @Test("known application and website defaults are conservative")
  func knownDefaultsAreConservative() {
    let defaults = DefaultActivityCategories.assignments

    #expect(
      defaults[.application(bundleIdentifier: "com.apple.Safari")] == .browser
    )
    #expect(
      defaults[.application(bundleIdentifier: "com.apple.dt.Xcode")] == .work
    )
    #expect(
      defaults[.application(bundleIdentifier: "com.valvesoftware.steam")]
        == .gaming
    )
    #expect(defaults[.website(domain: "github.com")] == .work)
    #expect(defaults[.website(domain: "youtube.com")] == .media)
    #expect(defaults[.website(domain: "reddit.com")] == .social)
    #expect(defaults[.website(domain: "twitch.tv")] == nil)
  }

  @Test("category totals equal their contributors")
  func categoryTotalsEqualContributors() {
    let report = DailyActivityReport(
      contributors: [
        DailyActivityContributor(
          subject: .application(bundleIdentifier: "com.apple.dt.Xcode"),
          displayName: "Xcode",
          category: .work,
          duration: 60
        ),
        DailyActivityContributor(
          subject: .website(domain: "github.com"),
          displayName: "github.com",
          category: .work,
          duration: 40
        ),
        DailyActivityContributor(
          subject: .website(domain: "youtube.com"),
          displayName: "youtube.com",
          category: .media,
          duration: 25
        ),
      ]
    )

    #expect(report.totalDuration == 125)
    #expect(report.total(for: .work)?.duration == 100)
    #expect(report.total(for: .media)?.duration == 25)
  }
}
