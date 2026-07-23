import Foundation

public enum ZoidMeetingDistributedBridge {
    public static let promptNotification = Notification.Name(
        "com.ziadnasreldin.zoidzero.atoll.meeting-prompt"
    )
    public static let actionNotification = Notification.Name(
        "com.ziadnasreldin.zoidzero.atoll.meeting-action"
    )
    public static let saveResultNotification = Notification.Name(
        "com.ziadnasreldin.zoidzero.atoll.meeting-save-result"
    )

    public static func postPrompt(
        _ prompt: ZoidMeetingPrompt,
        bundleIdentifier: String
    ) throws {
        try post(
            prompt,
            name: promptNotification,
            bundleIdentifier: bundleIdentifier
        )
    }

    public static func postAction(
        promptID: String,
        action: ZoidMeetingAction,
        bundleIdentifier: String
    ) throws {
        try post(
            ActionPayload(promptID: promptID, action: action),
            name: actionNotification,
            bundleIdentifier: bundleIdentifier
        )
    }

    public static func postSaveResult(
        promptID: String,
        result: ZoidMeetingSaveResult,
        bundleIdentifier: String
    ) throws {
        try post(
            SaveResultPayload(promptID: promptID, result: result),
            name: saveResultNotification,
            bundleIdentifier: bundleIdentifier
        )
    }

    public static func decodePrompt(
        _ notification: Notification
    ) -> (ZoidMeetingPrompt, String)? {
        decode(notification, as: ZoidMeetingPrompt.self)
    }

    public static func decodeAction(
        _ notification: Notification
    ) -> (ActionPayload, String)? {
        decode(notification, as: ActionPayload.self)
    }

    public static func decodeSaveResult(
        _ notification: Notification
    ) -> (SaveResultPayload, String)? {
        decode(notification, as: SaveResultPayload.self)
    }

    public struct ActionPayload: Codable, Sendable {
        public let promptID: String
        public let action: ZoidMeetingAction

        public init(promptID: String, action: ZoidMeetingAction) {
            self.promptID = promptID
            self.action = action
        }
    }

    public struct SaveResultPayload: Codable, Sendable {
        public let promptID: String
        public let result: ZoidMeetingSaveResult

        public init(promptID: String, result: ZoidMeetingSaveResult) {
            self.promptID = promptID
            self.result = result
        }
    }

    private static func post<Payload: Encodable>(
        _ payload: Payload,
        name: Notification.Name,
        bundleIdentifier: String
    ) throws {
        let data = try JSONEncoder().encode(payload)
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: nil,
            userInfo: [
                "payload": data.base64EncodedString(),
                "bundleIdentifier": bundleIdentifier,
            ],
            deliverImmediately: true
        )
    }

    private static func decode<Payload: Decodable>(
        _ notification: Notification,
        as type: Payload.Type
    ) -> (Payload, String)? {
        guard
            let userInfo = notification.userInfo,
            let encoded = userInfo["payload"] as? String,
            let data = Data(base64Encoded: encoded),
            let bundleIdentifier = userInfo["bundleIdentifier"] as? String,
            let payload = try? JSONDecoder().decode(type, from: data)
        else {
            return nil
        }
        return (payload, bundleIdentifier)
    }
}
