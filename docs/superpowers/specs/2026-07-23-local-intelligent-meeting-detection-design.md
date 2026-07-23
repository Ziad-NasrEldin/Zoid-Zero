# Local Intelligent Meeting Detection

## Summary

Zoid 0 will replace its single rigid meeting parser with a layered, fully local detection system.
Apple's on-device Foundation Models framework will be the primary detector on Apple Intelligence-capable Macs.
An improved deterministic English-Arabic parser will run automatically when the on-device model is unavailable or produces an unusable result.
Both paths will produce the same validated meeting-candidate structure and will always require explicit user confirmation before creating a Calendar event or Reminder.

## Goals

- Understand natural meeting language in English, Arabic, and mixed-language conversations.
- Recognize common written and spoken date and time variations.
- Extract multiple meetings from one analyzed screenshot.
- Show plausible candidates even when individual fields are uncertain.
- Keep screenshots, recognized text, prompts, model responses, and diagnostics on the Mac.
- Preserve explicit user confirmation before every Calendar or Reminder change.
- Continue detecting meetings when Apple Intelligence is unavailable by using an improved local parser.

## Non-Goals

- Zoid 0 will not upload screenshots or recognized text to any remote service.
- Zoid 0 will not use Private Cloud Compute or another cloud model as a fallback.
- Zoid 0 will not create, edit, or delete Calendar or Reminder data automatically.
- Zoid 0 will not send invitations, messages, or replies.
- The first release will not bundle or maintain a separate third-party language model.
- The first release will not train or ship a custom Foundation Models adapter.

## Supported Environment

The intelligent detector targets newer Apple Intelligence-capable Macs.
The app will check the on-device model's availability and language support at runtime.
Apple Intelligence may be disabled, not ready, unavailable in the current region, or unsupported for the detected language.
Any such condition will activate the improved parser without preventing meeting review.

## Detection Architecture

The detection pipeline will be:

1. ScreenCaptureKit captures a meaningfully changed screen.
2. Apple Vision performs local OCR.
3. The analyzer supplies recognized text, observation time, the Mac's current time zone, application name, and window title to the meeting-detection coordinator.
4. The coordinator uses Apple's on-device language model when it is available and supports the input language.
5. The model returns zero or more structured meeting extractions through guided generation.
6. A deterministic validator resolves and checks every extracted date, time, duration, and time zone.
7. Valid or plausible candidates enter the review queue.
8. If the model cannot run or its output cannot be validated, the improved parser analyzes the same local context.

The model prompt will not request prose.
It will request a bounded Swift structure representing zero or more possible meetings.
The model will never receive Calendar-writing tools or any capability that can cause external side effects.

## Candidate Structure

Each extracted meeting candidate will include:

- A stable local identifier.
- Meeting title.
- Person or people mentioned as ordinary text.
- Local start date and time.
- Explicit time zone when one was stated.
- Duration when stated or a clearly marked default otherwise.
- Source fingerprint.
- Detector source, either on-device model or parser fallback.
- Per-field certainty for the title, person, date, time, time zone, and duration.
- A short local evidence reference sufficient to explain why the candidate was detected.

Detector source and certainty metadata are local diagnostics.
They will not be written into Calendar event notes or Reminder titles.

## Date and Time Resolution

The validator, rather than the language model, will own final date construction.
It will resolve relative expressions against the screenshot observation time and the Mac's current Calendar and time zone.
It will support common forms including `3 pm`, `3 p.m.`, `14:30`, `2.30`, Arabic digits, and natural spoken expressions.
It will distinguish noon from midnight and handle weekday rollover, month and year boundaries, daylight-saving transitions, and explicit time zones.
It will reject impossible dates and invalid time components.
It will preserve uncertainty rather than inventing a precise value when the source text is ambiguous.

## Improved Parser Fallback

The fallback parser will remain fully local and deterministic.
It will support English, Arabic, and mixed-language text.
It will recognize punctuation variations, Arabic and Western digits, twelve-hour and twenty-four-hour time, common date forms, relative dates, durations, and explicit time zones.
It will scan for all candidate spans rather than returning only the first match.
Its output will use the same candidate and certainty structure as the on-device model.
It will pass through the same validator and review queue.

The fallback will run when:

- Apple Intelligence is disabled.
- The on-device model is not ready or unavailable.
- The input language or locale is unsupported by the model.
- Model execution times out or fails.
- Guided generation produces invalid or incomplete output that cannot form a plausible candidate.

## Uncertainty Behavior

Plausible candidates will be shown for review instead of being silently ignored.
Any uncertain date, time, duration, person, or time-zone field will be visibly highlighted.
The user can correct every extracted field.
A candidate with an unresolved required date or time cannot be confirmed until the user supplies a valid value.
Nothing will be scheduled merely because the detector reports high confidence.

## Multiple-Meeting Review Queue

One screenshot may produce zero, one, or several meeting candidates.
A single notification will summarize the number detected, such as "2 possible meetings detected."
Each meeting will have its own editable review card.
The user can confirm or dismiss each meeting independently.
The queue will preserve source order when that order can be determined.

Duplicate detection will compare normalized meeting identity and nearby source fingerprints.
Repeated screenshots or repeated mentions will not create redundant review cards.
A materially changed date, time, person, or title will remain reviewable rather than being incorrectly merged.

## Privacy and Safety

All OCR, model inference, parsing, validation, deduplication, and diagnostics will remain on the Mac.
No screenshot, recognized text, prompt, response, candidate, or diagnostic record will be uploaded.
The on-device model will only extract structured data and will have no scheduling capability.
Calendar and Reminder permissions will remain inside the explicit confirmation path.
Confirmation will create one personal Calendar event and one Apple Reminder for that candidate.
No attendee or invitation will be added.

## Error Handling

Model unavailability and model errors will degrade automatically to the parser.
Fallback use will not discard plausible candidates already extracted and validated.
Invalid candidate fields will be retained only when they can be shown safely as uncertain and corrected by the user.
Impossible or content-free extractions will be discarded locally.
Scheduling errors will remain separate from detection errors and will continue to identify the affected macOS permission or service.

## Testing and Evaluation

A versioned bilingual evaluation set will exercise the real detection coordinator and validator.
It will contain positive, uncertain, and negative examples in English, Arabic, and mixed-language text.
It will cover:

- Common punctuation and time formats.
- Arabic and Western digits.
- Spoken time expressions.
- Today, tomorrow, weekdays, numeric dates, explicit years, and time zones.
- Multiple meetings in one screenshot.
- Incomplete and ambiguous agreements.
- Ordinary non-meeting conversations.
- Apple Intelligence unavailable, disabled, unsupported-language, timeout, and invalid-output cases.
- Duplicate screenshots and repeated meeting mentions.
- Noon, midnight, day boundaries, daylight-saving changes, and Calendar edge cases.

Deterministic parser and validator tests will run in the normal test suite.
Foundation Models integration tests will use recorded structured fixtures for repeatability and will also have an opt-in evaluation path on a supported Mac.
The original `3 p.m.` and `2.30` failures will become permanent regression cases.

## Success Criteria

- Correct candidates and local times are shown for the agreed English and Arabic evaluation cases.
- Multiple meetings from one screenshot appear as independent review cards.
- Uncertain fields are visibly identified and editable.
- The fallback parser activates automatically for every specified model-unavailability condition.
- Repeated captures do not create duplicate review cards.
- Non-meeting examples do not produce confirmed scheduling actions.
- No Calendar event or Reminder can be created without explicit confirmation.
- Network inspection confirms that meeting detection sends no recognized text or screenshots off the Mac.
