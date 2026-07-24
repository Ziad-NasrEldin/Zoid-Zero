import Foundation

public protocol MeetingDetecting: Sendable {
  func detectMeetings(
    text: String,
    personHint: String,
    observedAt: Date,
    fingerprint: String
  ) async throws -> [MeetingCandidate]
}

public struct MeetingDetector: MeetingDetecting, Sendable {
  private let calendar: Calendar

  public init(calendar: Calendar = .current) {
    self.calendar = calendar
  }

  public func detectMeetings(
    text: String,
    personHint: String,
    observedAt: Date,
    fingerprint: String
  ) -> [MeetingCandidate] {
    detectMeetingCandidates(
      text: text,
      personHint: personHint,
      observedAt: observedAt,
      fingerprint: fingerprint
    )
  }

  private func detectMeetingCandidates(
    text: String,
    personHint: String,
    observedAt: Date,
    fingerprint: String
  ) -> [MeetingCandidate] {
    let normalized = normalize(text)
    return meetingSpans(in: normalized).enumerated().compactMap { index, span in
      detect(
        span: span,
        personHint: personHint,
        observedAt: observedAt,
        fingerprint: "\(fingerprint)#\(index)"
      )
    }
  }

  public func detect(
    text: String,
    personHint: String,
    observedAt: Date,
    fingerprint: String
  ) -> MeetingCandidate? {
    detectMeetingCandidates(
      text: text,
      personHint: personHint,
      observedAt: observedAt,
      fingerprint: fingerprint
    ).first
  }

  public func detectMeetings(
    text: String,
    personHint: String,
    observedAt: Date,
    fingerprint: String
  ) async throws -> [MeetingCandidate] {
    detectMeetingCandidates(
      text: text,
      personHint: personHint,
      observedAt: observedAt,
      fingerprint: fingerprint
    )
  }

  private func detect(
    span: String,
    personHint: String,
    observedAt: Date,
    fingerprint: String
  ) -> MeetingCandidate? {
    guard containsMeetingIntent(span),
      let dateMatch = match(
        #"\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|اليوم|بكرة|غدا|الأحد|الاثنين|الثلاثاء|الأربعاء|الخميس|الجمعة|السبت|\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}(?:[-/]\d{2,4})?)\b"#,
        in: span
      ),
      let timeMatch = firstMatch(
        #"\b(?:at|around|about|الساعة|حوالي|تقريبا)?\s*([01]?\d|2[0-3])(?:[:.]([0-5]\d))?\s*(am|pm|ص|م)?\b"#,
        in: span,
        after: dateMatch.result.range.location + dateMatch.result.range.length
      ),
      let hour = capture(timeMatch, 1).flatMap(Int.init),
      let start = resolve(
        dateExpression: dateMatch.value.lowercased(),
        hour: hour,
        minute: capture(timeMatch, 2).flatMap(Int.init) ?? 0,
        meridiem: capture(timeMatch, 3)?.lowercased(),
        observedAt: observedAt
      )
    else { return nil }

    let person = extractPerson(from: span) ?? personHint
    let duration = extractDuration(from: span)
    var uncertainFields: Set<MeetingCandidateField> = []
    if match(#"\b(around|about|maybe|possibly|حوالي|تقريبا|يمكن)\b"#, in: span) != nil {
      uncertainFields.insert(.time)
    }
    if person.isEmpty {
      uncertainFields.insert(.person)
    }
    if duration == nil {
      uncertainFields.insert(.duration)
    }

    return MeetingCandidate(
      id: fingerprint,
      title: person.isEmpty ? "Meeting" : "Meeting with \(person)",
      person: person,
      start: start,
      durationMinutes: duration ?? 30,
      sourceFingerprint: fingerprint,
      detectorSource: .parserFallback,
      uncertainFields: uncertainFields
    )
  }

  private func meetingSpans(in text: String) -> [String] {
    let intentPattern = #"\b(meet(?:ing)?|call|appointment|موعد|اجتماع|مكالمة)\b"#
    guard
      let regex = try? NSRegularExpression(
        pattern: intentPattern,
        options: [.caseInsensitive]
      )
    else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    let matches = regex.matches(in: text, range: range)
    return matches.enumerated().compactMap { index, match in
      let start = match.range.location
      let end = index + 1 < matches.count ? matches[index + 1].range.location : range.length
      guard let spanRange = Range(NSRange(location: start, length: end - start), in: text)
      else { return nil }
      return String(text[spanRange])
    }
  }

  private func containsMeetingIntent(_ text: String) -> Bool {
    match(#"\b(meet(?:ing)?|call|appointment|موعد|اجتماع|مكالمة)\b"#, in: text) != nil
  }

  private func extractPerson(from text: String) -> String? {
    let patterns = [
      #"\bwith\s+([\p{L}][\p{L}\s'-]{0,40}?)(?=\s+(?:today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|at|around|for)\b|[,.!?]|$)"#,
      #"\bcall\s+([\p{L}][\p{L}\s'-]{0,40}?)(?=\s+(?:today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|at|around|for)\b|[,.!?]|$)"#,
      #"\bمع\s+([\p{L}][\p{L}\s'-]{0,40}?)(?=\s+(?:اليوم|بكرة|غدا|الساعة|حوالي|لمدة)\b|[،,.!?]|$)"#,
    ]
    for pattern in patterns {
      if let result = match(pattern, in: text) {
        return capture(result, 1)?.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return nil
  }

  private func extractDuration(from text: String) -> Int? {
    guard
      let result = match(
        #"\b(?:for|لمدة)\s+(\d+)\s*(minutes?|mins?|hours?|hrs?|دقيقة|دقائق|ساعة|ساعات)\b"#,
        in: text
      ), let amount = capture(result, 1).flatMap(Int.init),
      let unit = capture(result, 2)?.lowercased()
    else { return nil }
    return unit.hasPrefix("h") || unit.hasPrefix("ساعة") ? amount * 60 : amount
  }

  private func resolve(
    dateExpression: String,
    hour: Int,
    minute: Int,
    meridiem: String?,
    observedAt: Date
  ) -> Date? {
    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    if hour > 12, meridiem != nil { return nil }
    let startOfDay = calendar.startOfDay(for: observedAt)
    let target: Date
    switch dateExpression {
    case "today", "اليوم":
      target = startOfDay
    case "tomorrow", "بكرة", "غدا":
      guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay)
      else { return nil }
      target = tomorrow
    default:
      let weekdays = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7,
        "الأحد": 1, "الاثنين": 2, "الثلاثاء": 3, "الأربعاء": 4,
        "الخميس": 5, "الجمعة": 6, "السبت": 7,
      ]
      if let weekday = weekdays[dateExpression] {
        let current = calendar.component(.weekday, from: observedAt)
        let days = max(1, (weekday - current + 7) % 7)
        guard let resolved = calendar.date(byAdding: .day, value: days, to: startOfDay)
        else { return nil }
        target = resolved
      } else {
        guard let resolved = resolveNumericDate(dateExpression, observedAt: observedAt)
        else { return nil }
        target = resolved
      }
    }

    let resolvedHour: Int
    switch meridiem {
    case "pm", "م":
      resolvedHour = hour < 12 ? hour + 12 : hour
    case "am", "ص":
      resolvedHour = hour == 12 ? 0 : hour
    case nil:
      resolvedHour = hour
    default:
      return nil
    }
    return calendar.date(bySettingHour: resolvedHour, minute: minute, second: 0, of: target)
  }

  private func resolveNumericDate(_ expression: String, observedAt: Date) -> Date? {
    let values = expression.split(whereSeparator: { $0 == "-" || $0 == "/" }).compactMap {
      Int($0)
    }
    guard values.count == 2 || values.count == 3 else { return nil }
    let observedYear = calendar.component(.year, from: observedAt)
    let year: Int
    let month: Int
    let day: Int
    if values[0] > 31 {
      year = values[0]
      month = values[1]
      day = values[2]
    } else {
      day = values[0]
      month = values[1]
      year = values.count == 3 ? normalizedYear(values[2]) : observedYear
    }
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    guard let date = calendar.date(from: components),
      calendar.dateComponents([.year, .month, .day], from: date)
        == DateComponents(year: year, month: month, day: day)
    else { return nil }
    return date
  }

  private func normalizedYear(_ year: Int) -> Int {
    year < 100 ? 2000 + year : year
  }

  private func normalize(_ text: String) -> String {
    let digits: [Character: Character] = [
      "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
      "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
    ]
    return String(text.map { digits[$0] ?? $0 })
      .replacingOccurrences(of: #"(?i)\ba\.?\s*m\.?\b"#, with: "am", options: .regularExpression)
      .replacingOccurrences(of: #"(?i)\bp\.?\s*m\.?\b"#, with: "pm", options: .regularExpression)
  }

  private func match(_ pattern: String, in text: String) -> Match? {
    firstMatch(pattern, in: text, after: 0)
  }

  private func firstMatch(_ pattern: String, in text: String, after location: Int) -> Match? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    else { return nil }
    let fullRange = NSRange(text.startIndex..., in: text)
    guard location <= fullRange.length else { return nil }
    let searchRange = NSRange(location: location, length: fullRange.length - location)
    guard let result = regex.firstMatch(in: text, range: searchRange),
      let range = Range(result.range, in: text)
    else { return nil }
    return Match(value: String(text[range]), result: result, text: text)
  }

  private func capture(_ match: Match, _ index: Int) -> String? {
    guard index < match.result.numberOfRanges,
      match.result.range(at: index).location != NSNotFound,
      let range = Range(match.result.range(at: index), in: match.text)
    else { return nil }
    return String(match.text[range])
  }
}

private struct Match {
  let value: String
  let result: NSTextCheckingResult
  let text: String
}
