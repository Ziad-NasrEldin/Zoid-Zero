import Foundation

public enum MeetingCandidateField: String, Codable, Hashable, Sendable {
  case title
  case person
  case date
  case time
  case timeZone
  case duration
}

public enum MeetingDetectorSource: String, Codable, Sendable {
  case foundationModels
  case parserFallback
}

public struct MeetingCandidate: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public var title: String
  public var person: String
  public var start: Date
  public var durationMinutes: Int
  public let sourceFingerprint: String
  public var detectorSource: MeetingDetectorSource?
  public var uncertainFields: Set<MeetingCandidateField>

  public init(
    id: String,
    title: String,
    person: String,
    start: Date,
    durationMinutes: Int = 30,
    sourceFingerprint: String,
    detectorSource: MeetingDetectorSource? = nil,
    uncertainFields: Set<MeetingCandidateField> = []
  ) {
    self.id = id
    self.title = title
    self.person = person
    self.start = start
    self.durationMinutes = durationMinutes
    self.sourceFingerprint = sourceFingerprint
    self.detectorSource = detectorSource
    self.uncertainFields = uncertainFields
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case person
    case start
    case durationMinutes
    case sourceFingerprint
    case detectorSource
    case uncertainFields
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    person = try container.decode(String.self, forKey: .person)
    start = try container.decode(Date.self, forKey: .start)
    durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
    sourceFingerprint = try container.decode(String.self, forKey: .sourceFingerprint)
    detectorSource = try container.decodeIfPresent(
      MeetingDetectorSource.self,
      forKey: .detectorSource
    )
    uncertainFields =
      try container.decodeIfPresent(
        Set<MeetingCandidateField>.self,
        forKey: .uncertainFields
      ) ?? []
  }
}

public struct ConfirmedMeeting: Equatable, Sendable {
  public let title: String
  public let person: String
  public let start: Date
  public let durationMinutes: Int

  public init(candidate: MeetingCandidate) {
    title = candidate.title
    person = candidate.person
    start = candidate.start
    durationMinutes = candidate.durationMinutes
  }
}

public struct CalendarEventRequest: Equatable, Sendable {
  public let title: String
  public let notes: String
  public let start: Date
  public let end: Date
  public let attendees: [String]

  public init(meeting: ConfirmedMeeting) {
    title = meeting.title
    notes = meeting.person.isEmpty ? "" : "Meeting with \(meeting.person)"
    start = meeting.start
    end = meeting.start.addingTimeInterval(TimeInterval(meeting.durationMinutes * 60))
    attendees = []
  }
}

public struct ReminderRequest: Equatable, Sendable {
  public let title: String
  public let due: Date

  public init(meeting: ConfirmedMeeting) {
    title =
      meeting.person.isEmpty
      ? meeting.title
      : "\(meeting.title) - \(meeting.person)"
    due = meeting.start
  }
}

public struct SchedulingReceipt: Codable, Equatable, Sendable {
  public let eventCreated: Bool
  public let reminderCreated: Bool

  public init(eventCreated: Bool, reminderCreated: Bool) {
    self.eventCreated = eventCreated
    self.reminderCreated = reminderCreated
  }
}
