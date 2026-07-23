import Foundation

public struct ZoidMeetingPrompt: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let participantName: String?
    public let startDate: Date
    public let endDate: Date
    public let timeZoneIdentifier: String

    public init(
        id: String,
        title: String,
        participantName: String?,
        startDate: Date,
        endDate: Date,
        timeZoneIdentifier: String
    ) {
        self.id = id
        self.title = title
        self.participantName = participantName
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var isValid: Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endDate > startDate
            && TimeZone(identifier: timeZoneIdentifier) != nil
    }
}

public enum ZoidMeetingAction: String, Codable, Sendable {
    case confirm
    case dismiss
    case timeout
}

public enum ZoidMeetingSaveResult: String, Codable, Sendable {
    case saved
    case failed
}

@MainActor
final class ZoidMeetingActionRouter {
    private var handlers: [String: (ZoidMeetingAction) -> Void] = [:]

    func register(
        promptID: String,
        handler: @escaping (ZoidMeetingAction) -> Void
    ) {
        handlers[promptID] = handler
    }

    func route(promptID: String, actionRawValue: String) {
        guard let action = ZoidMeetingAction(rawValue: actionRawValue),
              let handler = handlers.removeValue(forKey: promptID) else {
            return
        }
        handler(action)
    }

    func remove(promptID: String) {
        handlers.removeValue(forKey: promptID)
    }

    func hasHandler(for promptID: String) -> Bool {
        handlers[promptID] != nil
    }
}
