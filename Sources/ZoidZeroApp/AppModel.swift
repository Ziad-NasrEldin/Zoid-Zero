import AppKit
import CoreGraphics
import Foundation
import ZoidZeroCore
import ZoidZeroInfrastructure

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var pendingCandidates: [MeetingCandidate] = []
  @Published var receipt: SchedulingReceipt?
  @Published var errorMessage: String?
  @Published var schedulingPrivacyPane: String?
  @Published var isSaving = false
  @Published var captureHealth: CaptureHealthState
  @Published var dailyActivityReport = DailyActivityReport(contributors: [])
  @Published var selectedActivityDate = Calendar.current.startOfDay(for: Date())
  @Published var safariWebsiteTrackingState: SafariWebsiteTrackingState = .unavailable

  private let workflow: MeetingCaptureWorkflow
  private let atollMeetingClient: AtollMeetingInteractionClient
  private let runtime: ZoidRuntime
  private var eventTask: Task<Void, Never>?
  private var totalsTask: Task<Void, Never>?
  private var activeAtollPromptID: String?

  var candidate: MeetingCandidate? {
    pendingCandidates.first
  }

  var reviewProgress: String? {
    pendingCandidates.count > 1 ? "1 of \(pendingCandidates.count)" : nil
  }

  init() {
    let initialHealth: CaptureHealthState =
      CGPreflightScreenCaptureAccess()
      ? .monitoring
      : .screenRecordingPermissionNeeded
    captureHealth = initialHealth
    let atollMeetingClient = AtollMeetingInteractionClient()
    self.atollMeetingClient = atollMeetingClient
    let store = ZoidLocalStore()
    let scheduler = AppleSchedulingService()
    let workflow = MeetingCaptureWorkflow(
      source: EmptyCandidateSource(),
      notifier: SilentMeetingNotifier(),
      scheduler: scheduler,
      fingerprints: store,
      records: store
    )
    self.workflow = workflow

    let events = AsyncStream<RuntimeEvent>.makeStream()
    let healthCoordinator = CaptureHealthCoordinator(
      initial: initialHealth,
      continuation: events.continuation
    )
    let analyzer = ScreenAnalyzer()
    let pipeline = ChangedScreenPipeline(
      analyzer: { try await analyzer.analyze($0) },
      resultHandler: { result in
        let accepted = await workflow.handleDetectedCandidates(result.candidates)
        guard !accepted.isEmpty else { return }
        events.continuation.yield(.candidates(accepted))
      },
      healthHandler: {
        await healthCoordinator.pipelineChanged($0)
      }
    )
    let capture = ScreenCaptureService(
      pipeline: pipeline,
      healthHandler: {
        await healthCoordinator.captureChanged($0)
      }
    )
    let tracker = ApplicationActivityTracker(store: store)
    let activity = ApplicationActivityMonitor(tracker: tracker)
    let websiteActivity: SafariWebsiteActivityController?
    if let sharedRootURL = SafariActivityInbox.sharedRootURL() {
      websiteActivity = SafariWebsiteActivityController(
        inbox: SafariActivityInbox(rootURL: sharedRootURL),
        tracker: WebsiteActivityTracker(store: store),
        frontmostBundleIdentifier: {
          NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
      )
    } else {
      websiteActivity = nil
    }
    runtime = ZoidRuntime(
      capture: capture,
      activity: activity,
      websiteActivity: websiteActivity,
      categoryAssignments: store
    )

    eventTask = Task { [weak self] in
      for await event in events.stream {
        guard let self else { return }
        switch event {
        case .candidates(let candidates):
          for candidate in candidates
          where !self.pendingCandidates.contains(where: { $0.id == candidate.id }) {
            self.pendingCandidates.append(candidate)
            if self.activeAtollPromptID == nil {
              await self.presentInAtoll(candidate)
            }
          }
        case .health(let health):
          self.captureHealth = health
        }
      }
    }
    totalsTask = Task { [weak self] in
      guard let self else { return }
      await self.startRuntime()
      while !Task.isCancelled {
        await self.refreshDailyActivity()
        try? await Task.sleep(for: .seconds(30))
      }
    }
    AppTerminationCoordinator.shared.model = self
  }

  @discardableResult
  func confirm(_ edited: MeetingCandidate) async -> Bool {
    guard !isSaving else { return false }
    isSaving = true
    defer { isSaving = false }
    do {
      receipt = try await workflow.confirm(edited)
      pendingCandidates.removeAll { $0.id == edited.id }
      return true
    } catch {
      errorMessage = error.localizedDescription
      if let schedulingError = error as? AppleSchedulingService.SchedulingError {
        switch schedulingError {
        case .calendarPermissionDenied:
          schedulingPrivacyPane = "Privacy_Calendars"
        case .remindersPermissionDenied:
          schedulingPrivacyPane = "Privacy_Reminders"
        case .noReminderCalendar:
          schedulingPrivacyPane = nil
        }
      } else {
        schedulingPrivacyPane = nil
      }
      return false
    }
  }

  func clearError() {
    errorMessage = nil
    schedulingPrivacyPane = nil
  }

  func openSchedulingPrivacySettings() {
    guard let schedulingPrivacyPane,
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?\(schedulingPrivacyPane)"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

  func dismiss() {
    guard !pendingCandidates.isEmpty else { return }
    pendingCandidates.removeFirst()
  }

  func resetReceipt() {
    receipt = nil
  }

  func openScreenRecordingSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

  func showPreviousActivityDay() {
    guard
      let previous = Calendar.current.date(
        byAdding: .day,
        value: -1,
        to: selectedActivityDate
      )
    else { return }
    selectedActivityDate = previous
    Task { await refreshDailyActivity() }
  }

  func showNextActivityDay() {
    let today = Calendar.current.startOfDay(for: Date())
    guard
      selectedActivityDate < today,
      let next = Calendar.current.date(
        byAdding: .day,
        value: 1,
        to: selectedActivityDate
      )
    else { return }
    selectedActivityDate = min(next, today)
    Task { await refreshDailyActivity() }
  }

  func showTodayActivity() {
    selectedActivityDate = Calendar.current.startOfDay(for: Date())
    Task { await refreshDailyActivity() }
  }

  func setCategory(_ category: ActivityCategory, for subject: ActivitySubject) {
    Task {
      await runtime.setCategory(category, for: subject)
      await refreshDailyActivity()
    }
  }

  func openSafariExtensionPreferences() {
    SafariExtensionStatusReader.openPreferences()
  }

  func shutdown() async {
    totalsTask?.cancel()
    await runtime.stop()
    eventTask?.cancel()
  }

  private func startRuntime() async {
    await runtime.start()
  }

  private func presentInAtoll(_ candidate: MeetingCandidate) async {
    guard activeAtollPromptID == nil else { return }
    activeAtollPromptID = candidate.id

    let result = await atollMeetingClient.present(candidate) { [weak self] action in
      Task { @MainActor [weak self] in
        await self?.handleAtollAction(action, candidate: candidate)
      }
    }

    if result == .unavailable {
      activeAtollPromptID = nil
    }
  }

  private func handleAtollAction(
    _ action: MeetingQuickAction,
    candidate: MeetingCandidate
  ) async {
    guard activeAtollPromptID == candidate.id else { return }

    switch action {
    case .confirm:
      let saved = await confirm(candidate)
      try? await atollMeetingClient.report(
        promptID: candidate.id,
        result: saved ? .saved : .failed
      )
    case .dismiss:
      pendingCandidates.removeAll { $0.id == candidate.id }
    case .timeout:
      break
    }

    activeAtollPromptID = nil
  }

  private func refreshDailyActivity() async {
    dailyActivityReport = await runtime.dailyActivityReport(for: selectedActivityDate)
    safariWebsiteTrackingState = SafariWebsiteStateResolver.resolve(
      extensionEnabled: await SafariExtensionStatusReader.isEnabled(),
      controllerState: runtime.safariWebsiteTrackingState
    )
  }
}

private enum RuntimeEvent: Sendable {
  case candidates([MeetingCandidate])
  case health(CaptureHealthState)
}

private struct EmptyCandidateSource: MeetingCandidateSource {
  func nextCandidate() -> MeetingCandidate? {
    nil
  }
}

private struct SilentMeetingNotifier: MeetingNotifying {
  func notify(candidates: [MeetingCandidate]) async {}
}

private actor CaptureHealthCoordinator {
  private var captureState: CaptureHealthState
  private var isAnalyzing = false
  private let continuation: AsyncStream<RuntimeEvent>.Continuation

  init(
    initial: CaptureHealthState,
    continuation: AsyncStream<RuntimeEvent>.Continuation
  ) {
    captureState = initial
    self.continuation = continuation
  }

  func captureChanged(_ state: CaptureHealthState) {
    captureState = state
    continuation.yield(
      .health(
        isAnalyzing && state == .monitoring
          ? .analyzingChangedScreen
          : state
      )
    )
  }

  func pipelineChanged(_ state: CaptureHealthState) {
    switch state {
    case .analyzingChangedScreen:
      isAnalyzing = true
      if captureState == .monitoring {
        continuation.yield(.health(.analyzingChangedScreen))
      }
    case .monitoring:
      isAnalyzing = false
      continuation.yield(.health(captureState))
    case .captureError:
      isAnalyzing = false
      continuation.yield(.health(state))
    case .pausedWhileIdle, .screenRecordingPermissionNeeded:
      break
    }
  }
}
