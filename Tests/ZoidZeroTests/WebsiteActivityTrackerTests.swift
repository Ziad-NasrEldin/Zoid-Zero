import Foundation
import Testing

@testable import ZoidZeroCore
@testable import ZoidZeroInfrastructure

@Suite("Safari website activity")
struct WebsiteActivityTrackerTests {
  private let start = Date(timeIntervalSince1970: 1_753_200_000)
  private let safari = ApplicationIdentity(
    bundleIdentifier: "com.apple.Safari",
    displayName: "Safari"
  )

  @Test(
    "domain normalization keeps registrable domains private",
    arguments: [
      ("https://www.youtube.com/watch?v=secret", "youtube.com"),
      ("https://docs.example.co.uk/private?q=secret", "example.co.uk"),
      ("https://subdomain.github.io/project", "subdomain.github.io"),
      ("http://localhost:8080/private", "localhost"),
      ("http://192.168.1.20/private", "192.168.1.20"),
    ]
  )
  func normalizesDomains(input: String, expected: String) {
    #expect(RegistrableDomain.normalized(from: input) == expected)
  }

  @Test("malformed and non-web addresses are rejected")
  func rejectsMalformedAddresses() {
    #expect(RegistrableDomain.normalized(from: "not a url") == nil)
    #expect(RegistrableDomain.normalized(from: "file:///private/secret") == nil)
    #expect(RegistrableDomain.normalized(from: "about:blank") == nil)
  }

  @Test("tab changes create non-overlapping website intervals")
  func tabChangesCreateIntervals() async {
    let store = WebsiteStoreSpy()
    let tracker = WebsiteActivityTracker(store: store)

    await tracker.transition(
      to: "github.com",
      browser: safari,
      at: start
    )
    await tracker.transition(
      to: "youtube.com",
      browser: safari,
      at: start.addingTimeInterval(30)
    )
    await tracker.stop(at: start.addingTimeInterval(50))

    let intervals = await store.values
    #expect(intervals.map(\.website.domain) == ["github.com", "youtube.com"])
    #expect(intervals.map(\.duration) == [30, 20])
    #expect(intervals[0].end == intervals[1].start)
  }

  @Test("daily intervals include the current active website")
  func dailyIntervalsIncludeCurrentWebsite() async {
    let through = start.addingTimeInterval(35)
    let store = WebsiteStoreSpy()
    let tracker = WebsiteActivityTracker(store: store, now: { through })
    await tracker.transition(
      to: "github.com",
      browser: safari,
      at: start
    )

    #expect(
      await tracker.dailyIntervals(for: start) == [
        WebsiteActivityInterval(
          website: WebsiteIdentity(browser: safari, domain: "github.com"),
          start: start,
          end: through
        )
      ]
    )
  }

  @Test("website time replaces overlapping Safari time")
  func websiteTimeReplacesSafariTime() {
    let safariInterval = ApplicationActivityInterval(
      application: safari,
      start: start,
      end: start.addingTimeInterval(100)
    )
    let websiteIntervals = [
      WebsiteActivityInterval(
        website: WebsiteIdentity(browser: safari, domain: "github.com"),
        start: start.addingTimeInterval(20),
        end: start.addingTimeInterval(50)
      ),
      WebsiteActivityInterval(
        website: WebsiteIdentity(browser: safari, domain: "youtube.com"),
        start: start.addingTimeInterval(50),
        end: start.addingTimeInterval(80)
      ),
    ]

    let contributors = ActivityIntervalReconciler.reconcile(
      applications: [safariInterval],
      websites: websiteIntervals,
      categories: CategoryAssignmentResolver(
        defaults: [
          .application(bundleIdentifier: safari.bundleIdentifier): .browser,
          .website(domain: "github.com"): .work,
          .website(domain: "youtube.com"): .media,
        ]
      )
    )

    #expect(contributors.map(\.duration).reduce(0, +) == 100)
    #expect(
      contributors.first {
        $0.subject
          == .application(bundleIdentifier: safari.bundleIdentifier)
      }?.duration == 40
    )
    #expect(
      contributors.first {
        $0.subject == .website(domain: "github.com")
      }?.duration == 30
    )
    #expect(
      contributors.first {
        $0.subject == .website(domain: "youtube.com")
      }?.duration == 30
    )
  }

  @Test("missing website data remains generic Safari time")
  func missingWebsiteDataFallsBackToSafari() {
    let safariInterval = ApplicationActivityInterval(
      application: safari,
      start: start,
      end: start.addingTimeInterval(45)
    )

    let contributors = ActivityIntervalReconciler.reconcile(
      applications: [safariInterval],
      websites: [],
      categories: CategoryAssignmentResolver(
        defaults: [
          .application(bundleIdentifier: safari.bundleIdentifier): .browser
        ]
      )
    )

    #expect(contributors.count == 1)
    #expect(contributors[0].category == .browser)
    #expect(contributors[0].duration == 45)
  }

  @Test("expired tracking sessions reject extension events")
  func expiredSessionRejectsEvents() {
    let validator = TrackingSessionValidator(maximumAge: 30)

    #expect(
      validator.accepts(
        markerDate: start,
        eventDate: start.addingTimeInterval(29)
      )
    )
    #expect(
      !validator.accepts(
        markerDate: start,
        eventDate: start.addingTimeInterval(31)
      )
    )
    #expect(!validator.accepts(markerDate: nil, eventDate: start))
  }

  @Test("website intervals and user assignments persist together")
  func websiteIntervalsAndAssignmentsPersist() async {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let website = WebsiteIdentity(browser: safari, domain: "github.com")
    let subject = ActivitySubject.website(domain: website.domain)
    var store: ZoidLocalStore? = ZoidLocalStore(fileURL: fileURL)

    await store?.append(
      WebsiteActivityInterval(
        website: website,
        start: start,
        end: start.addingTimeInterval(25)
      )
    )
    await store?.setCategory(.work, for: subject)
    store = nil

    let reopened = ZoidLocalStore(fileURL: fileURL)
    #expect(
      await reopened.websiteIntervals(
        from: start.addingTimeInterval(-1),
        to: start.addingTimeInterval(30)
      ).map(\.duration) == [25]
    )
    #expect(await reopened.userCategoryAssignments()[subject] == .work)
  }
}

private actor WebsiteStoreSpy: WebsiteActivityStoring {
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
