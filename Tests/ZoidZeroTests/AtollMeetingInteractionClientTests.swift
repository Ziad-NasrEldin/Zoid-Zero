import AtollExtensionKit
import Foundation
import Testing
@testable import ZoidZeroCore
@testable import ZoidZeroInfrastructure

@Suite("Atoll meeting interaction")
@MainActor
struct AtollMeetingInteractionClientTests {
  @Test("meeting candidate maps to a native Atoll prompt")
  func mapsCandidate() async {
    let presenter = AtollMeetingPresenterSpy(isAtollInstalled: true)
    let client = AtollMeetingInteractionClient(presenter: presenter)
    let candidate = makeCandidate()

    let result = await client.present(candidate) { _ in }

    #expect(result == .presented)
    #expect(presenter.presentedPrompts.count == 1)
    #expect(presenter.presentedPrompts[0].id == candidate.id)
    #expect(presenter.presentedPrompts[0].title == candidate.title)
    #expect(presenter.presentedPrompts[0].participantName == candidate.person)
    #expect(presenter.presentedPrompts[0].startDate == candidate.start)
    #expect(
      presenter.presentedPrompts[0].endDate
        == candidate.start.addingTimeInterval(45 * 60)
    )
  }

  @Test("unavailable Atoll keeps the candidate without presenting")
  func unavailableAtoll() async {
    let presenter = AtollMeetingPresenterSpy(isAtollInstalled: false)
    let client = AtollMeetingInteractionClient(presenter: presenter)

    let result = await client.present(makeCandidate()) { _ in }

    #expect(result == .unavailable)
    #expect(presenter.presentedPrompts.isEmpty)
  }

  @Test("connection failure is a silent unavailable result")
  func connectionFailure() async {
    let presenter = AtollMeetingPresenterSpy(
      isAtollInstalled: true,
      presentError: TestError.connection
    )
    let client = AtollMeetingInteractionClient(presenter: presenter)

    let result = await client.present(makeCandidate()) { _ in }

    #expect(result == .unavailable)
  }

  @Test("Atoll action maps to the app-facing action")
  func mapsAction() async {
    let presenter = AtollMeetingPresenterSpy(isAtollInstalled: true)
    let client = AtollMeetingInteractionClient(presenter: presenter)
    var received: [MeetingQuickAction] = []

    _ = await client.present(makeCandidate()) { received.append($0) }
    presenter.send(.confirm)

    #expect(received == [.confirm])
  }

  @Test("signed ZoidZero app may connect to Atoll XPC")
  func hasAtollMachLookupEntitlement() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let entitlementURL = repositoryRoot
      .appendingPathComponent("Resources/ZoidZero.entitlements")
    let data = try Data(contentsOf: entitlementURL)
    let propertyList = try PropertyListSerialization.propertyList(
      from: data,
      format: nil
    ) as? [String: Any]
    let names = propertyList?[
      "com.apple.security.temporary-exception.mach-lookup.global-name"
    ] as? [String]

    #expect(names?.contains("com.ebullioscopic.Atoll.xpc") == true)
  }

  private func makeCandidate() -> MeetingCandidate {
    MeetingCandidate(
      id: "meeting-1",
      title: "Planning session",
      person: "Sarah",
      start: Date(timeIntervalSince1970: 1_800_000_000),
      durationMinutes: 45,
      sourceFingerprint: "fingerprint-1"
    )
  }
}

@MainActor
private final class AtollMeetingPresenterSpy: AtollMeetingPresenting {
  let isAtollInstalled: Bool
  let presentError: Error?
  private(set) var presentedPrompts: [ZoidMeetingPrompt] = []
  private(set) var reportedResults: [(String, ZoidMeetingSaveResult)] = []
  private var actionHandler: (@MainActor (ZoidMeetingAction) -> Void)?

  init(isAtollInstalled: Bool, presentError: Error? = nil) {
    self.isAtollInstalled = isAtollInstalled
    self.presentError = presentError
  }

  func presentZoidMeetingPrompt(
    _ prompt: ZoidMeetingPrompt,
    onAction: @escaping @MainActor (ZoidMeetingAction) -> Void
  ) async throws {
    if let presentError {
      throw presentError
    }
    presentedPrompts.append(prompt)
    actionHandler = onAction
  }

  func reportZoidMeetingSaveResult(
    promptID: String,
    result: ZoidMeetingSaveResult
  ) async throws {
    reportedResults.append((promptID, result))
  }

  func send(_ action: ZoidMeetingAction) {
    actionHandler?(action)
  }
}

private enum TestError: Error {
  case connection
}
