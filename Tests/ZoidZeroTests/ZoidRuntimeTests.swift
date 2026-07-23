import CoreGraphics
import Foundation
import Testing

@testable import ZoidZeroCore
@testable import ZoidZeroInfrastructure

@Suite("Zoid runtime lifecycle")
@MainActor
struct ZoidRuntimeTests {
  @Test("launch starts capture and application tracking")
  func launchStartsServices() async {
    let capture = CaptureServiceSpy()
    let activity = ActivityServiceSpy()
    let runtime = ZoidRuntime(capture: capture, activity: activity)

    await runtime.start()

    #expect(await capture.startCount == 1)
    #expect(activity.startCount == 1)
  }

  @Test("closing the window keeps both services running")
  func closingWindowDoesNotStopServices() async {
    let capture = CaptureServiceSpy()
    let activity = ActivityServiceSpy()
    let runtime = ZoidRuntime(capture: capture, activity: activity)
    await runtime.start()

    runtime.windowDidClose()

    #expect(await capture.stopCount == 0)
    #expect(activity.stopCount == 0)
  }

  @Test("explicit stop ends capture and finalizes activity")
  func explicitStopFinalizesServices() async {
    let capture = CaptureServiceSpy()
    let activity = ActivityServiceSpy()
    let runtime = ZoidRuntime(capture: capture, activity: activity)
    await runtime.start()

    await runtime.stop()

    #expect(await capture.stopCount == 1)
    #expect(activity.stopCount == 1)
  }

  @Test("launch and explicit stop own Safari website tracking")
  func lifecycleOwnsSafariTracking() async {
    let capture = CaptureServiceSpy()
    let activity = ActivityServiceSpy()
    let websites = WebsiteControllerSpy()
    let runtime = ZoidRuntime(
      capture: capture,
      activity: activity,
      websiteActivity: websites
    )

    await runtime.start()
    await runtime.stop()

    #expect(websites.startCount == 1)
    #expect(websites.stopCount == 1)
  }

  @Test("daily report replaces Safari time with categorized website time")
  func dailyReportReconcilesSafariTime() async {
    let start = Date(timeIntervalSince1970: 1_753_200_000)
    let safari = ApplicationIdentity(
      bundleIdentifier: "com.apple.Safari",
      displayName: "Safari"
    )
    let activity = ActivityServiceSpy(
      intervals: [
        ApplicationActivityInterval(
          application: safari,
          start: start,
          end: start.addingTimeInterval(60)
        )
      ]
    )
    let websites = WebsiteControllerSpy(
      intervals: [
        WebsiteActivityInterval(
          website: WebsiteIdentity(browser: safari, domain: "github.com"),
          start: start.addingTimeInterval(10),
          end: start.addingTimeInterval(40)
        )
      ]
    )
    let assignments = CategoryStoreSpy()
    await assignments.setCategory(
      .social,
      for: .website(domain: "github.com")
    )
    let runtime = ZoidRuntime(
      capture: CaptureServiceSpy(),
      activity: activity,
      websiteActivity: websites,
      categoryAssignments: assignments
    )

    let report = await runtime.dailyActivityReport(for: start)

    #expect(report.totalDuration == 60)
    #expect(
      report.contributors.first {
        $0.subject == .website(domain: "github.com")
      }?.category == .social
    )
    #expect(
      report.contributors.first {
        $0.subject
          == .application(bundleIdentifier: "com.apple.Safari")
      }?.duration == 30
    )
  }

  @Test("changed screen reaches one editable candidate across app sources")
  func changedScreenReachesConfirmationSeam() async {
    let notifications = RuntimeNotificationSpy()
    let workflow = MeetingCaptureWorkflow(
      source: EmptyCandidateSource(),
      notifier: notifications,
      scheduler: RuntimeSchedulingSpy(),
      fingerprints: InMemoryFingerprintStore()
    )
    let candidates = CandidateRecorder()
    let pipeline = ChangedScreenPipeline(
      configuration: .init(debounce: .zero, minimumOCRInterval: .zero),
      analyzer: { screen in
        ScreenAnalysisResult(
          screen: screen,
          recognizedText: "Meeting tomorrow at 3 pm",
          candidates: [
            sampleRuntimeCandidate(
              fingerprint: screen.fingerprint.identifier
            )
          ]
        )
      },
      resultHandler: { result in
        let accepted = await workflow.handleDetectedCandidates(result.candidates)
        for candidate in accepted {
          await candidates.append(candidate)
        }
      }
    )

    await pipeline.submit(runtimeScreen(applicationName: "Messages"))
    await pipeline.finishCurrentWork()

    #expect(await candidates.values.count == 1)
    #expect(await notifications.values.count == 1)
    #expect(await candidates.values.first?.title == "Planning call")
  }
}

private actor CaptureServiceSpy: ScreenCaptureControlling {
  private(set) var startCount = 0
  private(set) var stopCount = 0

  func start() {
    startCount += 1
  }

  func stop() {
    stopCount += 1
  }
}

@MainActor
private final class ActivityServiceSpy: ApplicationActivityControlling {
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private let intervals: [ApplicationActivityInterval]

  init(intervals: [ApplicationActivityInterval] = []) {
    self.intervals = intervals
  }

  func start() {
    startCount += 1
  }

  func stop() async {
    stopCount += 1
  }

  func dailyTotals(for date: Date) async -> [DailyApplicationTotal] {
    []
  }

  func dailyIntervals(for date: Date) async -> [ApplicationActivityInterval] {
    intervals
  }
}

@MainActor
private final class WebsiteControllerSpy: SafariWebsiteActivityControlling {
  private(set) var startCount = 0
  private(set) var stopCount = 0
  let intervals: [WebsiteActivityInterval]
  var state: SafariWebsiteTrackingState = .on

  init(intervals: [WebsiteActivityInterval] = []) {
    self.intervals = intervals
  }

  func start() async throws {
    startCount += 1
  }

  func stop() async {
    stopCount += 1
  }

  func dailyIntervals(for date: Date) async -> [WebsiteActivityInterval] {
    intervals
  }
}

private actor CategoryStoreSpy: CategoryAssignmentStoring {
  private var assignments: [ActivitySubject: ActivityCategory] = [:]

  func setCategory(_ category: ActivityCategory, for subject: ActivitySubject) {
    assignments[subject] = category
  }

  func userCategoryAssignments() -> [ActivitySubject: ActivityCategory] {
    assignments
  }
}

private actor RuntimeNotificationSpy: MeetingNotifying {
  private(set) var values: [MeetingCandidate] = []

  func notify(candidates: [MeetingCandidate]) {
    values.append(contentsOf: candidates)
  }
}

private struct RuntimeSchedulingSpy: MeetingScheduling {
  func schedule(_ meeting: ConfirmedMeeting) -> SchedulingReceipt {
    SchedulingReceipt(eventCreated: true, reminderCreated: true)
  }
}

private struct EmptyCandidateSource: MeetingCandidateSource {
  func nextCandidate() -> MeetingCandidate? {
    nil
  }
}

private actor CandidateRecorder {
  private(set) var values: [MeetingCandidate] = []

  func append(_ candidate: MeetingCandidate) {
    values.append(candidate)
  }
}

private func sampleRuntimeCandidate(fingerprint: String) -> MeetingCandidate {
  MeetingCandidate(
    id: fingerprint,
    title: "Planning call",
    person: "Mona",
    start: Date(timeIntervalSince1970: 1_753_300_000),
    sourceFingerprint: fingerprint
  )
}

private func runtimeScreen(applicationName: String) -> CapturedScreen {
  let bytes: [UInt8] = [255, 255, 255, 255]
  let provider = CGDataProvider(data: Data(bytes) as CFData)!
  let image = CGImage(
    width: 1,
    height: 1,
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    bytesPerRow: 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(
      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
    provider: provider,
    decode: nil,
    shouldInterpolate: false,
    intent: .defaultIntent
  )!
  return CapturedScreen(
    id: "screen",
    observedAt: Date(),
    applicationName: applicationName,
    windowTitle: "Conversation",
    fingerprint: VisualFingerprint(bytes: [1, 2, 3]),
    image: image
  )
}
