import Foundation
import ZoidZeroCore

public actor ZoidLocalStore:
  ApplicationActivityStoring,
  CategoryAssignmentStoring,
  FingerprintStoring,
  MeetingRecordStoring,
  WebsiteActivityStoring
{
  private struct ReceiptRecord: Codable {
    let sourceFingerprint: String
    let receipt: SchedulingReceipt
  }

  private struct State: Codable {
    var intervals: [ApplicationActivityInterval] = []
    var websiteIntervals: [WebsiteActivityInterval] = []
    var categoryAssignments: [ActivitySubject: ActivityCategory] = [:]
    var fingerprints: Set<String> = []
    var candidates: [MeetingCandidate] = []
    var receipts: [ReceiptRecord] = []

    private enum CodingKeys: String, CodingKey {
      case intervals
      case websiteIntervals
      case categoryAssignments
      case fingerprints
      case candidates
      case receipts
    }

    init() {}

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      intervals =
        try container.decodeIfPresent(
          [ApplicationActivityInterval].self,
          forKey: .intervals
        ) ?? []
      websiteIntervals =
        try container.decodeIfPresent(
          [WebsiteActivityInterval].self,
          forKey: .websiteIntervals
        ) ?? []
      categoryAssignments =
        try container.decodeIfPresent(
          [ActivitySubject: ActivityCategory].self,
          forKey: .categoryAssignments
        ) ?? [:]
      fingerprints =
        try container.decodeIfPresent(Set<String>.self, forKey: .fingerprints) ?? []
      candidates =
        try container.decodeIfPresent([MeetingCandidate].self, forKey: .candidates)
        ?? []
      receipts =
        try container.decodeIfPresent([ReceiptRecord].self, forKey: .receipts) ?? []
    }
  }

  private let fileURL: URL
  private var state: State

  public init(fileURL: URL? = nil) {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!.appendingPathComponent("ZoidZero", isDirectory: true)
    self.fileURL = fileURL ?? base.appendingPathComponent("store.json")
    if let data = try? Data(contentsOf: self.fileURL),
      let decoded = try? JSONDecoder.zoid.decode(State.self, from: data)
    {
      state = decoded
    } else {
      state = State()
    }
  }

  public var recordedCandidateCount: Int {
    state.candidates.count
  }

  public var recordedReceiptCount: Int {
    state.receipts.count
  }

  public func append(_ interval: ApplicationActivityInterval) {
    state.intervals.append(interval)
    persist()
  }

  public func intervals(
    from start: Date,
    to end: Date
  ) -> [ApplicationActivityInterval] {
    state.intervals.filter { $0.end > start && $0.start < end }
  }

  public func append(_ interval: WebsiteActivityInterval) {
    state.websiteIntervals.append(interval)
    persist()
  }

  public func websiteIntervals(
    from start: Date,
    to end: Date
  ) -> [WebsiteActivityInterval] {
    state.websiteIntervals.filter { $0.end > start && $0.start < end }
  }

  public func setCategory(
    _ category: ActivityCategory,
    for subject: ActivitySubject
  ) {
    state.categoryAssignments[subject] = category
    persist()
  }

  public func userCategoryAssignments() -> [ActivitySubject: ActivityCategory] {
    state.categoryAssignments
  }

  public func contains(_ fingerprint: String) -> Bool {
    state.fingerprints.contains(fingerprint)
  }

  public func insert(_ fingerprint: String) {
    state.fingerprints.insert(fingerprint)
    persist()
  }

  public func insertIfAbsent(_ fingerprint: String) -> Bool {
    let inserted = state.fingerprints.insert(fingerprint).inserted
    if inserted {
      persist()
    }
    return inserted
  }

  public func record(candidate: MeetingCandidate) {
    guard
      !state.candidates.contains(where: {
        $0.sourceFingerprint == candidate.sourceFingerprint
      })
    else { return }
    state.candidates.append(candidate)
    persist()
  }

  public func record(
    receipt: SchedulingReceipt,
    for candidate: MeetingCandidate
  ) {
    state.receipts.append(
      ReceiptRecord(
        sourceFingerprint: candidate.sourceFingerprint,
        receipt: receipt
      )
    )
    persist()
  }

  private func persist() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try JSONEncoder.zoid.encode(state).write(to: fileURL, options: .atomic)
    } catch {
      return
    }
  }
}

extension JSONEncoder {
  fileprivate static var zoid: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var zoid: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
