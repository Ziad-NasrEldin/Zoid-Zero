import Foundation

public protocol MeetingCandidateSource: Sendable {
  func nextCandidate() async throws -> MeetingCandidate?
}

public protocol MeetingNotifying: Sendable {
  func notify(candidates: [MeetingCandidate]) async
}

public protocol MeetingScheduling: Sendable {
  func schedule(_ meeting: ConfirmedMeeting) async throws -> SchedulingReceipt
}

public protocol FingerprintStoring: Sendable {
  func contains(_ fingerprint: String) async -> Bool
  func insert(_ fingerprint: String) async
  func insertIfAbsent(_ fingerprint: String) async -> Bool
}

public protocol MeetingRecordStoring: Sendable {
  func record(candidate: MeetingCandidate) async
  func record(
    receipt: SchedulingReceipt,
    for candidate: MeetingCandidate
  ) async
}

public actor InMemoryFingerprintStore: FingerprintStoring {
  private var fingerprints: Set<String> = []

  public init() {}

  public func contains(_ fingerprint: String) -> Bool {
    fingerprints.contains(fingerprint)
  }

  public func insert(_ fingerprint: String) {
    fingerprints.insert(fingerprint)
  }

  public func insertIfAbsent(_ fingerprint: String) -> Bool {
    fingerprints.insert(fingerprint).inserted
  }
}

public actor MeetingCaptureWorkflow {
  private let source: any MeetingCandidateSource
  private let notifier: any MeetingNotifying
  private let scheduler: any MeetingScheduling
  private let fingerprints: any FingerprintStoring
  private let records: (any MeetingRecordStoring)?

  public init(
    source: any MeetingCandidateSource,
    notifier: any MeetingNotifying,
    scheduler: any MeetingScheduling,
    fingerprints: any FingerprintStoring,
    records: (any MeetingRecordStoring)? = nil
  ) {
    self.source = source
    self.notifier = notifier
    self.scheduler = scheduler
    self.fingerprints = fingerprints
    self.records = records
  }

  public func checkForMeeting() async throws -> MeetingCandidate? {
    guard let candidate = try await source.nextCandidate() else { return nil }
    return await handleDetectedCandidate(candidate)
  }

  public func handleDetectedCandidate(
    _ candidate: MeetingCandidate
  ) async -> MeetingCandidate? {
    await handleDetectedCandidates([candidate]).first
  }

  public func handleDetectedCandidates(
    _ candidates: [MeetingCandidate]
  ) async -> [MeetingCandidate] {
    var accepted: [MeetingCandidate] = []
    for candidate in candidates {
      guard await fingerprints.insertIfAbsent(candidate.sourceFingerprint) else {
        continue
      }
      await records?.record(candidate: candidate)
      accepted.append(candidate)
    }
    if !accepted.isEmpty {
      await notifier.notify(candidates: accepted)
    }
    return accepted
  }

  public func confirm(_ candidate: MeetingCandidate) async throws -> SchedulingReceipt {
    let receipt = try await scheduler.schedule(ConfirmedMeeting(candidate: candidate))
    await records?.record(receipt: receipt, for: candidate)
    return receipt
  }
}
