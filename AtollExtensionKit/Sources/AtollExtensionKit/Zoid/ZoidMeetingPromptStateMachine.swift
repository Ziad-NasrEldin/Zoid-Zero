import Foundation

public enum ZoidMeetingPromptPhase: Equatable, Sendable {
    case idle
    case awaitingDecision
    case saving
    case saved
    case failed
}

public enum ZoidMeetingPromptEvent: Equatable, Sendable {
    case present(ZoidMeetingPrompt)
    case select(ZoidMeetingAction)
    case timeout
    case saveResult(ZoidMeetingSaveResult)
    case reset
}

public enum ZoidMeetingPromptEffect: Equatable, Sendable {
    case none
    case busy
    case send(ZoidMeetingAction)
    case sendAndClose(ZoidMeetingAction)
    case close(after: TimeInterval)
}

public struct ZoidMeetingPromptStateMachine: Sendable {
    public private(set) var prompt: ZoidMeetingPrompt?
    public private(set) var phase: ZoidMeetingPromptPhase = .idle

    public init() {}

    @discardableResult
    public mutating func handle(
        _ event: ZoidMeetingPromptEvent
    ) -> ZoidMeetingPromptEffect {
        switch event {
        case .present(let prompt):
            guard phase == .idle else { return .busy }
            self.prompt = prompt
            phase = .awaitingDecision
            return .none

        case .select(.confirm):
            guard phase == .awaitingDecision else { return .none }
            phase = .saving
            return .send(.confirm)

        case .select(.dismiss):
            guard phase == .awaitingDecision else { return .none }
            reset()
            return .sendAndClose(.dismiss)

        case .select(.timeout), .timeout:
            guard phase == .awaitingDecision else { return .none }
            reset()
            return .sendAndClose(.timeout)

        case .saveResult(.saved):
            guard phase == .saving else { return .none }
            phase = .saved
            return .close(after: 0.9)

        case .saveResult(.failed):
            guard phase == .saving else { return .none }
            phase = .failed
            return .close(after: 2)

        case .reset:
            reset()
            return .none
        }
    }

    private mutating func reset() {
        prompt = nil
        phase = .idle
    }
}
