import Foundation
import XCTest
@testable import AtollExtensionKit

final class ZoidMeetingPromptTests: XCTestCase {
    func testValidPromptRoundTripsThroughJSON() throws {
        let prompt = ZoidMeetingPrompt(
            id: "meeting-11111111",
            title: "Meeting with Sarah",
            participantName: "Sarah",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            timeZoneIdentifier: "Africa/Cairo"
        )

        let data = try JSONEncoder().encode(prompt)
        let decoded = try JSONDecoder().decode(ZoidMeetingPrompt.self, from: data)

        XCTAssertEqual(decoded, prompt)
        XCTAssertTrue(prompt.isValid)
    }

    func testPromptRejectsEndThatIsNotLaterThanStart() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let prompt = ZoidMeetingPrompt(
            id: "invalid-range",
            title: "Meeting",
            participantName: nil,
            startDate: date,
            endDate: date,
            timeZoneIdentifier: "Africa/Cairo"
        )

        XCTAssertFalse(prompt.isValid)
    }

    func testPromptRejectsUnknownTimeZone() {
        let prompt = ZoidMeetingPrompt(
            id: "invalid-zone",
            title: "Meeting",
            participantName: nil,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            timeZoneIdentifier: "Not/A_Time_Zone"
        )

        XCTAssertFalse(prompt.isValid)
    }

    @MainActor
    func testActionRouterDeliversOnceAndRemovesHandler() {
        let router = ZoidMeetingActionRouter()
        var received: [ZoidMeetingAction] = []
        router.register(promptID: "meeting-1") { received.append($0) }

        router.route(promptID: "meeting-1", actionRawValue: "confirm")
        router.route(promptID: "meeting-1", actionRawValue: "dismiss")

        XCTAssertEqual(received, [.confirm])
    }

    @MainActor
    func testActionRouterIgnoresUnknownAction() {
        let router = ZoidMeetingActionRouter()
        var received: [ZoidMeetingAction] = []
        router.register(promptID: "meeting-1") { received.append($0) }

        router.route(promptID: "meeting-1", actionRawValue: "unknown")

        XCTAssertTrue(received.isEmpty)
        XCTAssertTrue(router.hasHandler(for: "meeting-1"))
    }

    func testPromptStateMachineConfirmsThenAcceptsSavedResult() {
        var machine = ZoidMeetingPromptStateMachine()
        let prompt = makePrompt()

        XCTAssertEqual(machine.handle(.present(prompt)), .none)
        XCTAssertEqual(machine.phase, .awaitingDecision)
        XCTAssertEqual(machine.handle(.select(.confirm)), .send(.confirm))
        XCTAssertEqual(machine.phase, .saving)
        XCTAssertEqual(machine.handle(.saveResult(.saved)), .close(after: 0.9))
        XCTAssertEqual(machine.phase, .saved)
    }

    func testPromptStateMachineTimesOutWithoutSaving() {
        var machine = ZoidMeetingPromptStateMachine()

        _ = machine.handle(.present(makePrompt()))
        XCTAssertEqual(machine.handle(.timeout), .sendAndClose(.timeout))
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertNil(machine.prompt)
    }

    func testPromptStateMachineRejectsSecondPromptWhileActive() {
        var machine = ZoidMeetingPromptStateMachine()

        XCTAssertEqual(machine.handle(.present(makePrompt())), .none)
        XCTAssertEqual(machine.handle(.present(makePrompt(id: "meeting-2"))), .busy)
        XCTAssertEqual(machine.prompt?.id, "meeting-1")
    }

    private func makePrompt(id: String = "meeting-1") -> ZoidMeetingPrompt {
        ZoidMeetingPrompt(
            id: id,
            title: "Meeting with Sarah",
            participantName: "Sarah",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            timeZoneIdentifier: "Africa/Cairo"
        )
    }
}
