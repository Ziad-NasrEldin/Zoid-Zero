import Foundation
import Testing

@testable import ZoidZeroCore
@testable import ZoidZeroInfrastructure

@Test("confirmed Screenwatch agreement creates one private event and reminder")
func confirmedAgreementCreatesPrivateOutputs() async throws {
  let notifications = NotificationSpy()
  let scheduling = SchedulingSpy()
  let detected = try #require(
    MeetingDetector().detect(
      text: "Meeting with Mona tomorrow at 3 pm for 45 minutes",
      personHint: "",
      observedAt: Date(timeIntervalSince1970: 1_753_276_496),
      fingerprint: "fixture"
    )
  )
  let workflow = MeetingCaptureWorkflow(
    source: FixedSource(candidate: detected),
    notifier: notifications,
    scheduler: scheduling,
    fingerprints: InMemoryFingerprintStore()
  )

  let candidate = try #require(await workflow.checkForMeeting())
  #expect(await notifications.candidates == [candidate])

  let receipt = try await workflow.confirm(candidate)

  #expect(await scheduling.events.count == 1)
  #expect(await scheduling.reminders.count == 1)
  #expect(await scheduling.events.first?.attendees.isEmpty == true)
  #expect(receipt.eventCreated)
  #expect(receipt.reminderCreated)
}

@Test("repeated screenshot notifies only once")
func repeatedScreenshotNotifiesOnlyOnce() async throws {
  let candidate = sampleCandidate()
  let notifications = NotificationSpy()
  let scheduling = SchedulingSpy()
  let workflow = MeetingCaptureWorkflow(
    source: FixedSource(candidate: candidate),
    notifier: notifications,
    scheduler: scheduling,
    fingerprints: InMemoryFingerprintStore()
  )

  #expect(try await workflow.checkForMeeting() == candidate)
  #expect(try await workflow.checkForMeeting() == nil)
  #expect(await notifications.candidates.count == 1)
  #expect(await scheduling.events.isEmpty)
  #expect(await scheduling.reminders.isEmpty)
}

@Test("concurrent duplicate detections notify only once")
func concurrentDuplicateDetectionsNotifyOnlyOnce() async {
  let candidate = sampleCandidate()
  let notifications = NotificationSpy()
  let workflow = MeetingCaptureWorkflow(
    source: FixedSource(candidate: nil),
    notifier: notifications,
    scheduler: SchedulingSpy(),
    fingerprints: YieldingFingerprintStore()
  )

  await withTaskGroup(of: Void.self) { group in
    for _ in 0..<20 {
      group.addTask {
        _ = await workflow.handleDetectedCandidate(candidate)
      }
    }
  }

  #expect(await notifications.candidates.count == 1)
}

@Test("two meetings from one screen are accepted and notified as one batch")
func multipleMeetingsAreAcceptedAsOneBatch() async {
  let notifications = NotificationSpy()
  let workflow = MeetingCaptureWorkflow(
    source: FixedSource(candidate: nil),
    notifier: notifications,
    scheduler: SchedulingSpy(),
    fingerprints: InMemoryFingerprintStore()
  )
  let first = sampleCandidate(id: "first", hourOffset: 0)
  let second = sampleCandidate(id: "second", hourOffset: 1)

  let accepted = await workflow.handleDetectedCandidates([first, second])

  #expect(accepted == [first, second])
  #expect(await notifications.batches == [[first, second]])
}

@Test("a repeated candidate does not replace another pending meeting")
func repeatedCandidateIsRemovedFromBatch() async {
  let notifications = NotificationSpy()
  let workflow = MeetingCaptureWorkflow(
    source: FixedSource(candidate: nil),
    notifier: notifications,
    scheduler: SchedulingSpy(),
    fingerprints: InMemoryFingerprintStore()
  )
  let first = sampleCandidate(id: "first", hourOffset: 0)
  let second = sampleCandidate(id: "second", hourOffset: 1)

  _ = await workflow.handleDetectedCandidates([first])
  let accepted = await workflow.handleDetectedCandidates([first, second])

  #expect(accepted == [second])
  #expect(await notifications.batches == [[first], [second]])
}

@Test("dismissed candidate creates nothing")
func dismissedCandidateCreatesNothing() async throws {
  let notifications = NotificationSpy()
  let scheduling = SchedulingSpy()
  let workflow = MeetingCaptureWorkflow(
    source: FixedSource(candidate: sampleCandidate()),
    notifier: notifications,
    scheduler: scheduling,
    fingerprints: InMemoryFingerprintStore()
  )

  _ = try await workflow.checkForMeeting()

  #expect(await notifications.candidates.count == 1)
  #expect(await scheduling.events.isEmpty)
  #expect(await scheduling.reminders.isEmpty)
}

@Test("confirmed edits are the values that get scheduled")
func confirmedEditsAreScheduled() async throws {
  let notifications = NotificationSpy()
  let scheduling = SchedulingSpy()
  let workflow = MeetingCaptureWorkflow(
    source: FixedSource(candidate: sampleCandidate()),
    notifier: notifications,
    scheduler: scheduling,
    fingerprints: InMemoryFingerprintStore()
  )
  var edited = try #require(try await workflow.checkForMeeting())
  edited.title = "Planning review"
  edited.person = "Nour"
  edited.durationMinutes = 60

  _ = try await workflow.confirm(edited)

  #expect(await scheduling.events.first?.title == "Planning review")
  #expect(await scheduling.events.first?.notes == "Meeting with Nour")
  #expect(await scheduling.reminders.first?.title == "Planning review - Nour")
}

@Test("calendar permission denial identifies Calendar and offers recovery")
func calendarPermissionDenialIsActionable() {
  let error = AppleSchedulingService.SchedulingError.calendarPermissionDenied

  #expect(error.errorDescription == "Calendar access is required to save this meeting.")
  #expect(error.requiresPrivacySettings)
}

@Test("reminder permission denial identifies Reminders and offers recovery")
func reminderPermissionDenialIsActionable() {
  let error = AppleSchedulingService.SchedulingError.remindersPermissionDenied

  #expect(error.errorDescription == "Reminders access is required to save this meeting.")
  #expect(error.requiresPrivacySettings)
}

@Test("Arabic agreement and Arabic digits are detected locally")
func arabicAgreementIsDetected() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "Africa/Cairo"))
  let observedAt = try #require(
    ISO8601DateFormatter().date(from: "2026-07-23T09:00:00+02:00")
  )

  let candidate = try #require(
    MeetingDetector(calendar: calendar).detect(
      text: "عندنا اجتماع بكرة الساعة ٣ م لمدة ٤٥ دقيقة",
      personHint: "سارة",
      observedAt: observedAt,
      fingerprint: "arabic-fixture"
    )
  )

  #expect(candidate.person == "سارة")
  #expect(candidate.durationMinutes == 45)
  #expect(calendar.component(.hour, from: candidate.start) == 15)
}

private actor NotificationSpy: MeetingNotifying {
  private(set) var candidates: [MeetingCandidate] = []
  private(set) var batches: [[MeetingCandidate]] = []

  func notify(candidates: [MeetingCandidate]) {
    batches.append(candidates)
    self.candidates.append(contentsOf: candidates)
  }
}

private actor SchedulingSpy: MeetingScheduling {
  private(set) var events: [CalendarEventRequest] = []
  private(set) var reminders: [ReminderRequest] = []

  func schedule(_ meeting: ConfirmedMeeting) -> SchedulingReceipt {
    events.append(.init(meeting: meeting))
    reminders.append(.init(meeting: meeting))
    return SchedulingReceipt(eventCreated: true, reminderCreated: true)
  }
}

private struct FixedSource: MeetingCandidateSource {
  let candidate: MeetingCandidate?

  func nextCandidate() -> MeetingCandidate? {
    candidate
  }
}

private actor YieldingFingerprintStore: FingerprintStoring {
  private var fingerprints: Set<String> = []

  func contains(_ fingerprint: String) async -> Bool {
    await Task.yield()
    return fingerprints.contains(fingerprint)
  }

  func insert(_ fingerprint: String) async {
    await Task.yield()
    fingerprints.insert(fingerprint)
  }

  func insertIfAbsent(_ fingerprint: String) async -> Bool {
    await Task.yield()
    return fingerprints.insert(fingerprint).inserted
  }
}

private func sampleCandidate() -> MeetingCandidate {
  sampleCandidate(id: "same-image", hourOffset: 0)
}

private func sampleCandidate(id: String, hourOffset: TimeInterval) -> MeetingCandidate {
  MeetingCandidate(
    id: id,
    title: "Meeting with Mona",
    person: "Mona",
    start: Date(timeIntervalSince1970: 1_784_802_600 + hourOffset * 3_600),
    sourceFingerprint: id
  )
}
