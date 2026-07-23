import Foundation
import Testing

@testable import ZoidZeroCore

@Suite("Meeting detector")
struct MeetingDetectorTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Africa/Cairo")!
    return calendar
  }

  private var observedAt: Date {
    ISO8601DateFormatter().date(from: "2026-07-23T09:00:00+03:00")!
  }

  @Test(
    "common English and Arabic time punctuation resolves correctly",
    arguments: [
      ("Meeting tomorrow at 3 p.m.", 15, 0),
      ("Meeting tomorrow at 2.30 pm", 14, 30),
      ("اجتماع بكرة الساعة ٣:٤٥ م", 15, 45),
    ]
  )
  func parsesCommonTimePunctuation(
    text: String,
    expectedHour: Int,
    expectedMinute: Int
  ) throws {
    let candidates = MeetingDetector(calendar: calendar).detectMeetings(
      text: text,
      personHint: "",
      observedAt: observedAt,
      fingerprint: "punctuation"
    )

    let candidate = try #require(candidates.first)
    #expect(calendar.component(.hour, from: candidate.start) == expectedHour)
    #expect(calendar.component(.minute, from: candidate.start) == expectedMinute)
  }

  @Test("two meeting sentences produce two candidates in source order")
  func parsesMultipleMeetings() throws {
    let candidates = MeetingDetector(calendar: calendar).detectMeetings(
      text: """
        Meeting with Mona tomorrow at 3 p.m.
        Call Nour Friday at 2.30 pm.
        """,
      personHint: "",
      observedAt: observedAt,
      fingerprint: "multiple"
    )

    #expect(candidates.count == 2)
    #expect(candidates.map(\.person) == ["Mona", "Nour"])
    #expect(calendar.component(.hour, from: candidates[0].start) == 15)
    #expect(calendar.component(.hour, from: candidates[1].start) == 14)
    #expect(calendar.component(.minute, from: candidates[1].start) == 30)
  }

  @Test(
    "approximate English and Arabic times remain visible for review",
    arguments: [
      "Maybe meet Sara tomorrow around 3 pm",
      "اجتماع مع سارة بكرة حوالي ٣ م",
    ]
  )
  func marksApproximateTimesUncertain(text: String) throws {
    let candidates = MeetingDetector(calendar: calendar).detectMeetings(
      text: text,
      personHint: "",
      observedAt: observedAt,
      fingerprint: "uncertain"
    )

    let candidate = try #require(candidates.first)
    #expect(candidate.uncertainFields.contains(.time))
  }

  @Test(
    "clock and date mentions without meeting intent are ignored",
    arguments: [
      "The clock says 3 p.m. tomorrow.",
      "التاريخ بكرة والساعة ٣ م",
    ]
  )
  func ignoresNonMeetingText(text: String) {
    let candidates = MeetingDetector(calendar: calendar).detectMeetings(
      text: text,
      personHint: "",
      observedAt: observedAt,
      fingerprint: "negative"
    )

    #expect(candidates.isEmpty)
  }
}
