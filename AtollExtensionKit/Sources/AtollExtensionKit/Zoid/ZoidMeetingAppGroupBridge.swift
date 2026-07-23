import Foundation

public enum ZoidMeetingAppGroupBridge {
    public static let appGroupIdentifier =
        "377QC32T9T.group.com.ziadnasreldin.zoidzero"

    public static func postPrompt(
        _ prompt: ZoidMeetingPrompt,
        bundleIdentifier: String
    ) throws {
        try write(
            Envelope(payload: prompt, bundleIdentifier: bundleIdentifier),
            filename: "prompt.json"
        )
    }

    public static func takePrompt() throws -> (ZoidMeetingPrompt, String)? {
        try take(ZoidMeetingPrompt.self, filename: "prompt.json")
    }

    public static func postAction(
        promptID: String,
        action: ZoidMeetingAction,
        bundleIdentifier: String
    ) throws {
        try write(
            Envelope(
                payload: ActionPayload(promptID: promptID, action: action),
                bundleIdentifier: bundleIdentifier
            ),
            filename: "action.json"
        )
    }

    public static func takeAction() throws -> (ActionPayload, String)? {
        try take(ActionPayload.self, filename: "action.json")
    }

    public static func postSaveResult(
        promptID: String,
        result: ZoidMeetingSaveResult,
        bundleIdentifier: String
    ) throws {
        try write(
            Envelope(
                payload: SaveResultPayload(promptID: promptID, result: result),
                bundleIdentifier: bundleIdentifier
            ),
            filename: "save-result.json"
        )
    }

    public static func takeSaveResult() throws -> (SaveResultPayload, String)? {
        try take(SaveResultPayload.self, filename: "save-result.json")
    }

    public struct ActionPayload: Codable, Sendable {
        public let promptID: String
        public let action: ZoidMeetingAction
    }

    public struct SaveResultPayload: Codable, Sendable {
        public let promptID: String
        public let result: ZoidMeetingSaveResult
    }

    private struct Envelope<Payload: Codable>: Codable {
        let payload: Payload
        let bundleIdentifier: String
    }

    private static func bridgeDirectory() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw BridgeError.appGroupUnavailable
        }
        let directory = container.appendingPathComponent(
            "AtollMeetingBridge",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func write<Payload: Codable>(
        _ envelope: Envelope<Payload>,
        filename: String
    ) throws {
        let data = try JSONEncoder().encode(envelope)
        try data.write(
            to: bridgeDirectory().appendingPathComponent(filename),
            options: .atomic
        )
    }

    private static func take<Payload: Codable>(
        _ type: Payload.Type,
        filename: String
    ) throws -> (Payload, String)? {
        let url = try bridgeDirectory().appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        let envelope = try JSONDecoder().decode(
            Envelope<Payload>.self,
            from: data
        )
        return (envelope.payload, envelope.bundleIdentifier)
    }

    public enum BridgeError: Error {
        case appGroupUnavailable
    }
}
