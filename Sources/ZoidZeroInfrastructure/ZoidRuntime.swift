import Foundation
import ZoidZeroCore

@MainActor
public final class ZoidRuntime {
  private let capture: any ScreenCaptureControlling
  private let activity: any ApplicationActivityControlling
  private let websiteActivity: (any SafariWebsiteActivityControlling)?
  private let categoryAssignments: (any CategoryAssignmentStoring)?
  private let automaticCategories: (any AutomaticCategoryStoring)?
  private let categorizer: AutomaticActivityCategorizer?
  private var started = false

  public init(
    capture: any ScreenCaptureControlling,
    activity: any ApplicationActivityControlling,
    websiteActivity: (any SafariWebsiteActivityControlling)? = nil,
    categoryAssignments: (any CategoryAssignmentStoring)? = nil,
    automaticCategories: (any AutomaticCategoryStoring)? = nil,
    categorizer: AutomaticActivityCategorizer? = nil
  ) {
    self.capture = capture
    self.activity = activity
    self.websiteActivity = websiteActivity
    self.categoryAssignments = categoryAssignments
    self.automaticCategories = automaticCategories
    self.categorizer = categorizer
  }

  public func start() async {
    guard !started else { return }
    started = true
    activity.start()
    try? await websiteActivity?.start()
    await categorizer?.backfill()
    await capture.start()
  }

  public func windowDidClose() {}

  public func dailyTotals(for date: Date = Date()) async -> [DailyApplicationTotal] {
    await activity.dailyTotals(for: date)
  }

  public func dailyActivityReport(
    for date: Date = Date()
  ) async -> DailyActivityReport {
    let applications = await activity.dailyIntervals(for: date)
    let websites = await websiteActivity?.dailyIntervals(for: date) ?? []
    await categorizer?.categorize(
      applications.map {
        let subject = ActivitySubject.application(
          bundleIdentifier: $0.application.bundleIdentifier
        )
        return ActivityMetadata(
          subject: subject,
          displayName: $0.application.displayName
        )
      }
        + websites.map {
          let subject = ActivitySubject.website(domain: $0.website.domain)
          return ActivityMetadata(subject: subject, displayName: $0.website.domain)
        }
    )
    let userAssignments = await categoryAssignments?.userCategoryAssignments() ?? [:]
    let automaticAssignments =
      await automaticCategories?.automaticCategoryAssignments() ?? [:]
    let resolver = CategoryAssignmentResolver(
      defaults: DefaultActivityCategories.assignments,
      automaticAssignments: automaticAssignments,
      userAssignments: userAssignments
    )
    return DailyActivityReport(
      contributors: ActivityIntervalReconciler.reconcile(
        applications: applications,
        websites: websites,
        categories: resolver
      )
    )
  }

  public var safariWebsiteTrackingState: SafariWebsiteTrackingState {
    websiteActivity?.state ?? .unavailable
  }

  public func setCategory(
    _ category: ActivityCategory,
    for subject: ActivitySubject
  ) async {
    await categoryAssignments?.setCategory(category, for: subject)
  }

  public func resetCategory(
    for subject: ActivitySubject,
    displayName: String
  ) async {
    await categoryAssignments?.resetCategory(for: subject)
    await categorizer?.reset(
      ActivityMetadata(subject: subject, displayName: displayName)
    )
  }

  public func stop() async {
    guard started else { return }
    started = false
    await capture.stop()
    await websiteActivity?.stop()
    await activity.stop()
  }
}
