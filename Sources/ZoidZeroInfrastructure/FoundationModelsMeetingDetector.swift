import Foundation
import FoundationModels
import ZoidZeroCore

public struct FoundationModelsMeetingDetector: MeetingDetecting {
  public enum DetectionError: Error {
    case unavailable
    case unsupportedLanguage
    case unusableOutput
  }

  public init() {}

  public func detectMeetings(
    text: String,
    personHint: String,
    observedAt: Date,
    fingerprint: String
  ) async throws -> [MeetingCandidate] {
    let model = SystemLanguageModel.default
    guard model.availability == .available else {
      throw DetectionError.unavailable
    }
    let locale = Locale(identifier: containsArabic(text) ? "ar" : "en")
    guard model.supportsLocale(locale) else {
      throw DetectionError.unsupportedLanguage
    }

    let session = LanguageModelSession(
      model: model,
      tools: [],
      instructions: """
        Extract every independent meeting agreement from the supplied OCR text.
        Support English, Arabic, and mixed-language text.
        Copy the original date and time expressions exactly.
        Never invent a missing date or time.
        Return an empty meetings array when the text contains no meeting agreement.
        Mark approximate or inferred fields as uncertain.
        Do not produce prose and do not perform any action.
        """
    )
    let formatter = ISO8601DateFormatter()
    let prompt = """
      Observation time: \(formatter.string(from: observedAt))
      Local time zone: \(TimeZone.current.identifier)
      Window context: \(personHint)
      OCR text:
      \(text)
      """
    let response = try await session.respond(
      to: prompt,
      generating: GeneratedMeetingBatch.self
    )
    guard !response.content.meetings.isEmpty else { return [] }

    let parser = MeetingDetector()
    let candidates = response.content.meetings.enumerated().compactMap {
      index, generated -> MeetingCandidate? in
      guard !generated.dateExpression.isEmpty, !generated.timeExpression.isEmpty else {
        return nil
      }
      let personClause = generated.person.isEmpty ? "" : " with \(generated.person)"
      let durationClause =
        generated.durationMinutes > 0 ? " for \(generated.durationMinutes) minutes" : ""
      let canonical = """
        Meeting\(personClause) \(generated.dateExpression) at \
        \(generated.timeExpression)\(durationClause)
        """
      guard
        var candidate = parser.detect(
          text: canonical,
          personHint: generated.person.isEmpty ? personHint : generated.person,
          observedAt: observedAt,
          fingerprint: "\(fingerprint)#model-\(index)"
        )
      else { return nil }
      if !generated.title.isEmpty {
        candidate.title = generated.title
      }
      candidate.detectorSource = .foundationModels
      candidate.uncertainFields.formUnion(
        generated.uncertainFields.compactMap(MeetingCandidateField.init(rawValue:))
      )
      return candidate
    }
    guard !candidates.isEmpty else {
      throw DetectionError.unusableOutput
    }
    return candidates
  }

  private func containsArabic(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0x0600...0x06FF).contains(Int($0.value)) }
  }
}

@Generable
private struct GeneratedMeetingBatch {
  @Guide(description: "Every independent meeting found in source order")
  var meetings: [GeneratedMeeting]
}

@Generable
private struct GeneratedMeeting {
  @Guide(description: "Concise meeting title, or an empty string")
  var title: String

  @Guide(description: "Person named in the meeting, or an empty string")
  var person: String

  @Guide(description: "Original explicit or relative date expression")
  var dateExpression: String

  @Guide(description: "Original time expression including meridiem when present")
  var timeExpression: String

  @Guide(description: "Duration in minutes, or zero when absent", .range(0...1_440))
  var durationMinutes: Int

  @Guide(
    description: "Names of uncertain fields: title, person, date, time, timeZone, duration"
  )
  var uncertainFields: [String]
}
