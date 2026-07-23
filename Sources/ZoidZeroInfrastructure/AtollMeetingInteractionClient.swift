import AtollExtensionKit
import Foundation
import ZoidZeroCore

@MainActor
public protocol AtollMeetingPresenting: AnyObject {
  var isAtollInstalled: Bool { get }

  func presentZoidMeetingPrompt(
    _ prompt: ZoidMeetingPrompt,
    onAction: @escaping @MainActor (ZoidMeetingAction) -> Void
  ) async throws

  func reportZoidMeetingSaveResult(
    promptID: String,
    result: ZoidMeetingSaveResult
  ) async throws
}

extension AtollClient: AtollMeetingPresenting {}

public enum AtollMeetingPresentationResult: Equatable, Sendable {
  case presented
  case unavailable
}

public enum MeetingQuickAction: Equatable, Sendable {
  case confirm
  case dismiss
  case timeout

  init(_ action: ZoidMeetingAction) {
    switch action {
    case .confirm: self = .confirm
    case .dismiss: self = .dismiss
    case .timeout: self = .timeout
    }
  }
}

public enum MeetingQuickSaveResult: Sendable {
  case saved
  case failed

  var atollResult: ZoidMeetingSaveResult {
    switch self {
    case .saved: return .saved
    case .failed: return .failed
    }
  }
}

@MainActor
public final class AtollMeetingInteractionClient {
  private let presenter: any AtollMeetingPresenting

  public init(presenter: any AtollMeetingPresenting = AtollClient.shared) {
    self.presenter = presenter
  }

  public func present(
    _ candidate: MeetingCandidate,
    onAction: @escaping @MainActor (MeetingQuickAction) -> Void
  ) async -> AtollMeetingPresentationResult {
    guard presenter.isAtollInstalled else {
      return .unavailable
    }

    let person = candidate.person.trimmingCharacters(in: .whitespacesAndNewlines)
    let prompt = ZoidMeetingPrompt(
      id: candidate.id,
      title: candidate.title,
      participantName: person.isEmpty ? nil : person,
      startDate: candidate.start,
      endDate: candidate.start.addingTimeInterval(
        TimeInterval(candidate.durationMinutes * 60)
      ),
      timeZoneIdentifier: TimeZone.current.identifier
    )

    do {
      try await presenter.presentZoidMeetingPrompt(prompt) { action in
        onAction(MeetingQuickAction(action))
      }
      return .presented
    } catch {
      return .unavailable
    }
  }

  public func report(
    promptID: String,
    result: MeetingQuickSaveResult
  ) async throws {
    try await presenter.reportZoidMeetingSaveResult(
      promptID: promptID,
      result: result.atollResult
    )
  }
}
