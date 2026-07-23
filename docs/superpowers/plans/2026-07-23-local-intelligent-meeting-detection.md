# Local Intelligent Meeting Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single rigid meeting parser with private on-device Apple Foundation Models extraction, an improved bilingual fallback parser, deterministic time validation, and a multi-meeting review queue.

**Architecture:** `ZoidZeroCore` will define detector-neutral extraction, certainty, validation, deduplication, and fallback behavior. `ZoidZeroInfrastructure` will adapt Apple's on-device Foundation Models framework to that interface. `ScreenAnalyzer`, the workflow, and the SwiftUI app will carry arrays of independently reviewable candidates through one shared path.

**Tech Stack:** Swift 6.3, macOS 26, Swift Testing, SwiftUI, Foundation Models, Foundation Calendar, Apple Vision, UserNotifications, EventKit.

## Global Constraints

- All screenshots, OCR text, prompts, responses, candidates, and diagnostics remain on the Mac.
- The primary detector uses Apple's on-device Foundation Models framework only.
- Private Cloud Compute and remote model providers are prohibited.
- English, Arabic, and mixed-language text are supported.
- The improved deterministic parser runs automatically when the on-device model is unavailable, unsupported, fails, times out, or produces unusable output.
- One screenshot may produce zero, one, or multiple meeting candidates.
- Plausible candidates are shown for review even when fields are uncertain.
- A candidate with an unresolved required date or time cannot be confirmed.
- No Calendar event or Reminder is created without explicit user confirmation.
- Existing unrelated worktree changes must remain untouched.
- Every UI-visible result requires an in-app Browser proof screenshot.

## File Structure

- Create `Sources/ZoidZeroCore/MeetingDetection.swift` for detector-neutral contexts, extraction values, certainty metadata, protocols, coordinator behavior, and errors.
- Create `Sources/ZoidZeroCore/MeetingTemporalValidator.swift` for converting extracted date and time text into checked `Date` values.
- Replace `Sources/ZoidZeroCore/MeetingDetector.swift` with the improved English-Arabic fallback parser that returns all matches.
- Create `Sources/ZoidZeroInfrastructure/FoundationModelsMeetingExtractor.swift` for model availability checks and guided structured generation.
- Modify `Sources/ZoidZeroCore/MeetingModels.swift` to persist detector source and field certainty without exposing them to Calendar notes.
- Modify `Sources/ZoidZeroCore/CaptureModels.swift` so one analysis contains `[MeetingCandidate]`.
- Modify `Sources/ZoidZeroInfrastructure/ScreenAnalyzer.swift` to call the asynchronous coordinator.
- Modify `Sources/ZoidZeroCore/MeetingCaptureWorkflow.swift` to accept candidate batches and deduplicate by normalized meeting identity.
- Modify `Sources/ZoidZeroInfrastructure/ZoidLocalStore.swift` for backward-compatible candidate metadata decoding and meeting-identity fingerprints.
- Modify `Sources/ZoidZeroInfrastructure/DesktopMeetingNotifier.swift` to summarize a candidate batch in one notification.
- Modify `Sources/ZoidZeroApp/AppModel.swift` to own a review queue.
- Modify `Sources/ZoidZeroApp/MeetingCaptureView.swift` to review candidates independently and highlight uncertain fields.
- Modify `Package.swift` and `Scripts/build-app.sh` to require macOS 26.
- Add focused tests under `Tests/ZoidZeroTests`.

---

### Task 1: Detector-Neutral Models and Deterministic Temporal Validation

**Files:**
- Create: `Sources/ZoidZeroCore/MeetingDetection.swift`
- Create: `Sources/ZoidZeroCore/MeetingTemporalValidator.swift`
- Modify: `Sources/ZoidZeroCore/MeetingModels.swift`
- Test: `Tests/ZoidZeroTests/MeetingTemporalValidatorTests.swift`

**Interfaces:**
- Consumes: `Foundation.Calendar`, the observation `Date`, and the Mac time zone.
- Produces: `MeetingDetectionContext`, `RawMeetingExtraction`, `MeetingFieldCertainty`, `MeetingCandidateMetadata`, `MeetingExtracting.extractMeetings(from:)`, and `MeetingTemporalValidator.validate(_:context:)`.

- [ ] **Step 1: Write failing model and validator tests**

Add tests that construct a Gregorian Calendar in `Africa/Cairo` and verify:

```swift
@Test("validates common English and Arabic time forms")
func validatesCommonTimeForms() throws {
  let context = detectionContext(observedAt: "2026-07-23T09:00:00+03:00")
  let cases = [
    ("tomorrow", "3 p.m.", 15, 0),
    ("tomorrow", "2.30 pm", 14, 30),
    ("بكرة", "٣:٤٥ م", 15, 45),
    ("2026-07-25", "14:30", 14, 30),
  ]
  for (dateText, timeText, hour, minute) in cases {
    let result = try #require(
      MeetingTemporalValidator(calendar: context.calendar)
        .validate(raw(date: dateText, time: timeText), context: context)
    )
    #expect(context.calendar.component(.hour, from: result.start) == hour)
    #expect(context.calendar.component(.minute, from: result.start) == minute)
  }
}

@Test("preserves uncertainty and rejects impossible values")
func preservesUncertaintyAndRejectsImpossibleValues() throws {
  let context = detectionContext(observedAt: "2026-07-23T09:00:00+03:00")
  let uncertain = try #require(
    MeetingTemporalValidator(calendar: context.calendar).validate(
      raw(date: "tomorrow", time: "around 3", certainty: .uncertain),
      context: context
    )
  )
  #expect(uncertain.metadata.time == .uncertain)
  #expect(
    MeetingTemporalValidator(calendar: context.calendar).validate(
      raw(date: "2026-02-30", time: "25:90"),
      context: context
    ) == nil
  )
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```bash
swift test --filter MeetingTemporalValidator
```

Expected: compilation fails because the detection and validator types do not exist.

- [ ] **Step 3: Add detector-neutral types**

Define:

```swift
public enum MeetingFieldCertainty: String, Codable, Sendable {
  case certain
  case uncertain
  case missing
}

public enum MeetingDetectorSource: String, Codable, Sendable {
  case foundationModels
  case parserFallback
}

public struct MeetingCandidateMetadata: Codable, Equatable, Sendable {
  public var title: MeetingFieldCertainty
  public var person: MeetingFieldCertainty
  public var date: MeetingFieldCertainty
  public var time: MeetingFieldCertainty
  public var timeZone: MeetingFieldCertainty
  public var duration: MeetingFieldCertainty
  public var source: MeetingDetectorSource
  public var evidence: String
}

public struct MeetingDetectionContext: Sendable {
  public let text: String
  public let observedAt: Date
  public let timeZone: TimeZone
  public let applicationName: String
  public let windowTitle: String
  public let sourceFingerprint: String

  public var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = timeZone
    return value
  }
}

public struct RawMeetingExtraction: Equatable, Sendable {
  public var title: String
  public var person: String
  public var dateExpression: String
  public var timeExpression: String
  public var timeZoneIdentifier: String?
  public var durationMinutes: Int?
  public var metadata: MeetingCandidateMetadata
}

public protocol MeetingExtracting: Sendable {
  func extractMeetings(from context: MeetingDetectionContext) async throws
    -> [RawMeetingExtraction]
}
```

Extend `MeetingCandidate` with a backward-compatible optional/defaulted `metadata` property.
Keep its existing initializer source-compatible by defaulting metadata to a certain parser result.

- [ ] **Step 4: Implement deterministic validation**

Implement `MeetingTemporalValidator` with:

- Arabic digit normalization.
- `today`, `tomorrow`, Arabic equivalents, weekdays, ISO dates, and locale-aware numeric dates.
- `am`, `pm`, `a.m.`, `p.m.`, Arabic meridiems, colon, dot, and twenty-four-hour formats.
- Explicit IANA time-zone identifiers when supplied.
- strict Calendar round-trip checks to reject impossible dates and times.
- preservation of per-field certainty.

The public entry point must be:

```swift
public func validate(
  _ raw: RawMeetingExtraction,
  context: MeetingDetectionContext
) -> MeetingCandidate?
```

Use `"\(context.sourceFingerprint)#\(index-or-normalized-identity)"` as the stable candidate ID at the coordinator layer rather than inside the validator.

- [ ] **Step 5: Run the focused tests**

Run:

```bash
swift test --filter MeetingTemporalValidator
```

Expected: all temporal validation tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/ZoidZeroCore/MeetingDetection.swift Sources/ZoidZeroCore/MeetingTemporalValidator.swift Sources/ZoidZeroCore/MeetingModels.swift Tests/ZoidZeroTests/MeetingTemporalValidatorTests.swift
git commit -m "feat: add validated meeting extraction models"
```

### Task 2: Improved English-Arabic Multi-Meeting Parser

**Files:**
- Modify: `Sources/ZoidZeroCore/MeetingDetector.swift`
- Test: `Tests/ZoidZeroTests/MeetingDetectorTests.swift`
- Modify: `Tests/ZoidZeroTests/MeetingCaptureWorkflowTests.swift`

**Interfaces:**
- Consumes: `MeetingDetectionContext`.
- Produces: `MeetingDetector.extractMeetings(from:) async -> [RawMeetingExtraction]`.

- [ ] **Step 1: Write failing parser regression tests**

Cover at minimum:

```swift
@Test("parses punctuation variants and Arabic digits")
func parsesPunctuationVariants() async throws {
  let detector = MeetingDetector()
  let cases = [
    ("Meeting tomorrow at 3 p.m.", 15, 0),
    ("Meeting tomorrow at 2.30 pm", 14, 30),
    ("اجتماع بكرة الساعة ٣:٤٥ م", 15, 45),
  ]
  for (text, expectedHour, expectedMinute) in cases {
    let candidates = try await validatedFallback(text)
    let candidate = try #require(candidates.first)
    #expect(calendar.component(.hour, from: candidate.start) == expectedHour)
    #expect(calendar.component(.minute, from: candidate.start) == expectedMinute)
  }
}

@Test("extracts two independent meetings")
func extractsTwoMeetings() async throws {
  let candidates = try await validatedFallback(
    "Meeting with Mona tomorrow at 3 p.m. Call Nour Friday at 2.30 pm."
  )
  #expect(candidates.count == 2)
  #expect(candidates.map(\.person) == ["Mona", "Nour"])
}

@Test("returns plausible uncertain candidates")
func returnsUncertainCandidate() async throws {
  let candidates = try await validatedFallback("Maybe meet Sara tomorrow around 3")
  #expect(candidates.count == 1)
  #expect(candidates[0].metadata.time == .uncertain)
}
```

Add negative examples for ordinary mentions of dates, clocks, and names without meeting intent.

- [ ] **Step 2: Run and verify red**

Run:

```bash
swift test --filter MeetingDetector
```

Expected: failures for dotted meridiems, dotted minutes, multiple candidates, and uncertain forms.

- [ ] **Step 3: Replace first-match parsing with span-based parsing**

Implement `MeetingDetector: MeetingExtracting`.
Split text into sentence-like spans while preserving English and Arabic punctuation.
For each span:

- require meeting intent;
- extract all recognizable date-time pairs;
- accept dotted and undotted meridiems;
- accept colon and dot minute separators;
- normalize Arabic digits;
- extract person and duration when available;
- return uncertainty metadata for `around`, `maybe`, `تقريباً`, `حوالي`, or missing optional fields;
- keep required date and time expressions present before producing a parser result.

Do not call Calendar APIs from the parser.
Return raw extractions for the validator.

- [ ] **Step 4: Run focused and existing workflow tests**

Run:

```bash
swift test --filter MeetingDetector
swift test --filter MeetingCaptureWorkflow
```

Expected: all parser and existing workflow tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ZoidZeroCore/MeetingDetector.swift Tests/ZoidZeroTests/MeetingDetectorTests.swift Tests/ZoidZeroTests/MeetingCaptureWorkflowTests.swift
git commit -m "feat: improve bilingual meeting parser"
```

### Task 3: Apple Foundation Models Primary Extractor and Automatic Fallback

**Files:**
- Modify: `Package.swift`
- Modify: `Scripts/build-app.sh`
- Create: `Sources/ZoidZeroCore/MeetingDetectionCoordinator.swift`
- Create: `Sources/ZoidZeroInfrastructure/FoundationModelsMeetingExtractor.swift`
- Test: `Tests/ZoidZeroTests/MeetingDetectionCoordinatorTests.swift`
- Test: `Tests/ZoidZeroTests/FoundationModelsMeetingExtractorTests.swift`

**Interfaces:**
- Consumes: `MeetingExtracting`, `MeetingTemporalValidator`, and `SystemLanguageModel.default`.
- Produces: `MeetingDetectionCoordinator.detect(in:) async -> [MeetingCandidate]`.

- [ ] **Step 1: Write failing coordinator tests**

Use recording extractors to prove:

```swift
@Test("uses valid primary results without fallback")
func usesPrimary() async throws {
  let primary = ExtractorStub(result: [.success([validRawMeeting])])
  let fallback = ExtractorStub(result: [.success([fallbackRawMeeting])])
  let result = await coordinator(primary: primary, fallback: fallback).detect(in: context)
  #expect(result.count == 1)
  #expect(result[0].metadata.source == .foundationModels)
  #expect(await fallback.callCount == 0)
}

@Test("falls back for unavailable failed or invalid primary output")
func fallsBack() async throws {
  for primaryResult in [
    Result<[RawMeetingExtraction], Error>.failure(TestError.unavailable),
    .success([]),
    .success([impossibleRawMeeting]),
  ] {
    let result = await coordinator(primaryResult: primaryResult).detect(in: context)
    #expect(result.first?.metadata.source == .parserFallback)
  }
}
```

Also verify stable unique IDs and that duplicate raw extractions within one batch are collapsed.

- [ ] **Step 2: Run and verify red**

Run:

```bash
swift test --filter MeetingDetectionCoordinator
```

Expected: compilation fails because the coordinator does not exist.

- [ ] **Step 3: Implement the coordinator**

Implement an actor that:

- asks the primary extractor first;
- validates every primary extraction;
- uses fallback only when the primary cannot run or yields no valid candidate;
- assigns detector source metadata;
- creates stable candidate IDs from source fingerprint plus normalized meeting identity;
- returns all unique candidates in source order;
- never merges meetings with materially different person, title, date, or time.

An empty successful primary result means "no meeting" only when the model completed normally.
Distinguish that from invalid output by having the primary throw `MeetingExtractionError.invalidOutput`.

- [ ] **Step 4: Add the Foundation Models adapter**

Raise the package and app build deployment target from macOS 14 to macOS 26.
Import `FoundationModels`.
Define a private `@Generable` response containing an array of generated meeting values with strings and certainty enums.
Give `LanguageModelSession` instructions that:

- extract only meetings supported by the supplied text;
- return every independent meeting;
- never invent a missing date or time;
- preserve the original date/time expression;
- support English, Arabic, and mixed language;
- return structured data only.

Before calling the session:

- check `SystemLanguageModel.default.availability`;
- verify the relevant locale with `supportsLocale`;
- map unavailable, unsupported, guardrail, and generation failures to typed local errors;
- never enable Private Cloud Compute;
- never provide tools or side-effect closures.

- [ ] **Step 5: Test adapter mapping without relying on live model output**

Extract availability and response mapping behind internal protocols.
Use stubs to verify `.available`, Apple Intelligence disabled, model not ready, unsupported language, invalid generated values, and a two-meeting response.
Keep one opt-in supported-Mac smoke test disabled by default through an environment guard:

```swift
guard ProcessInfo.processInfo.environment["ZOID_RUN_LOCAL_MODEL_TESTS"] == "1"
else { return }
```

- [ ] **Step 6: Run focused tests and build**

Run:

```bash
swift test --filter MeetingDetectionCoordinator
swift test --filter FoundationModelsMeetingExtractor
swift build
```

Expected: focused tests and package build pass on the installed macOS 26.5 SDK.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Scripts/build-app.sh Sources/ZoidZeroCore/MeetingDetectionCoordinator.swift Sources/ZoidZeroInfrastructure/FoundationModelsMeetingExtractor.swift Tests/ZoidZeroTests/MeetingDetectionCoordinatorTests.swift Tests/ZoidZeroTests/FoundationModelsMeetingExtractorTests.swift
git commit -m "feat: add on-device meeting intelligence"
```

### Task 4: Carry Candidate Batches Through Capture, Storage, Notification, and Deduplication

**Files:**
- Modify: `Sources/ZoidZeroCore/CaptureModels.swift`
- Modify: `Sources/ZoidZeroCore/MeetingCaptureWorkflow.swift`
- Modify: `Sources/ZoidZeroInfrastructure/ScreenAnalyzer.swift`
- Modify: `Sources/ZoidZeroInfrastructure/ZoidLocalStore.swift`
- Modify: `Sources/ZoidZeroInfrastructure/DesktopMeetingNotifier.swift`
- Modify: `Sources/ZoidZeroApp/AppModel.swift`
- Test: `Tests/ZoidZeroTests/ChangedScreenPipelineTests.swift`
- Test: `Tests/ZoidZeroTests/ScreenCaptureStorageTests.swift`
- Test: `Tests/ZoidZeroTests/MeetingCaptureWorkflowTests.swift`
- Test: `Tests/ZoidZeroTests/ZoidRuntimeTests.swift`

**Interfaces:**
- Consumes: `MeetingDetectionCoordinator.detect(in:)`.
- Produces: `ScreenAnalysisResult.candidates`, `MeetingCaptureWorkflow.handleDetectedCandidates(_:)`, and queued `RuntimeEvent.candidates`.

- [ ] **Step 1: Write failing batch-flow tests**

Verify:

- `ScreenAnalyzer` returns two candidates from one OCR result.
- `ScreenAnalysisResult` persists both candidates.
- the workflow records and returns both unique meetings from one screenshot;
- repeated nearby screenshots are deduplicated by normalized meeting identity, not only whole-screen fingerprint;
- two materially different meetings from the same screenshot are retained;
- the notifier receives one batch with the accepted count.

The workflow test must assert:

```swift
let accepted = await workflow.handleDetectedCandidates([meetingAtThree, meetingAtTwoThirty])
#expect(accepted.count == 2)
#expect(await notifications.batches.map(\.count) == [2])
```

- [ ] **Step 2: Run and verify red**

Run:

```bash
swift test --filter MeetingCaptureWorkflow
swift test --filter ChangedScreenPipeline
swift test --filter ScreenCaptureStorage
```

Expected: compilation failures at single-candidate interfaces.

- [ ] **Step 3: Convert capture and workflow interfaces to arrays**

Change:

```swift
public let candidate: MeetingCandidate?
```

to:

```swift
public let candidates: [MeetingCandidate]
```

Change `MeetingNotifying` to:

```swift
func notify(candidates: [MeetingCandidate]) async
```

Add:

```swift
public func handleDetectedCandidates(
  _ candidates: [MeetingCandidate]
) async -> [MeetingCandidate]
```

Perform one atomic identity insertion per candidate.
Record every accepted candidate.
Notify once with the complete accepted batch.

- [ ] **Step 4: Update storage and notifications**

Persist metadata with backward-compatible decoding defaults for older records.
Store normalized meeting identities independently from screen fingerprints.
Create one notification:

- title: `"Possible meetings detected"` for multiple candidates;
- body: `"\(count) meetings are ready for review."`;
- singular copy remains `"Possible meeting detected"`.

- [ ] **Step 5: Wire the live analyzer**

Construct `MeetingDetectionContext` from recognized text, observation date, `TimeZone.current`, application name, window title, and screen fingerprint.
Initialize `ScreenAnalyzer` with a `MeetingDetectionCoordinator` whose primary is `FoundationModelsMeetingExtractor` and fallback is `MeetingDetector`.
Yield all accepted candidates to the app queue.

- [ ] **Step 6: Run all non-UI tests**

Run:

```bash
swift test
```

Expected: all Swift tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/ZoidZeroCore/CaptureModels.swift Sources/ZoidZeroCore/MeetingCaptureWorkflow.swift Sources/ZoidZeroInfrastructure/ScreenAnalyzer.swift Sources/ZoidZeroInfrastructure/ZoidLocalStore.swift Sources/ZoidZeroInfrastructure/DesktopMeetingNotifier.swift Sources/ZoidZeroApp/AppModel.swift Tests/ZoidZeroTests/ChangedScreenPipelineTests.swift Tests/ZoidZeroTests/ScreenCaptureStorageTests.swift Tests/ZoidZeroTests/MeetingCaptureWorkflowTests.swift Tests/ZoidZeroTests/ZoidRuntimeTests.swift
git commit -m "feat: queue multiple detected meetings"
```

### Task 5: Uncertainty-Aware Multi-Meeting Review UI

**Files:**
- Modify: `Sources/ZoidZeroApp/AppModel.swift`
- Modify: `Sources/ZoidZeroApp/MeetingCaptureView.swift`
- Test: `Tests/ZoidZeroTests/MeetingReviewQueueTests.swift`

**Interfaces:**
- Consumes: `AppModel.candidates: [MeetingCandidate]` and per-field certainty metadata.
- Produces: independent confirm/dismiss behavior and visible uncertain-field treatment.

- [ ] **Step 1: Read the required UI skill**

Read `/Users/ziadnasreldin/.agents/skills/emil-design-eng/SKILL.md` completely before editing the SwiftUI view.
Keep the existing SUMI-E Ink design system authoritative.

- [ ] **Step 2: Write failing review-queue state tests**

Move queue operations into a small testable `MeetingReviewQueue` value or actor.
Verify:

```swift
@Test("confirm and dismiss advance independently")
func advancesQueue() {
  var queue = MeetingReviewQueue([first, second])
  #expect(queue.current == first)
  queue.removeCurrent()
  #expect(queue.current == second)
  queue.removeCurrent()
  #expect(queue.current == nil)
}
```

Also verify duplicate IDs do not enter the queue and new accepted batches append without replacing the current review.

- [ ] **Step 3: Run and verify red**

Run:

```bash
swift test --filter MeetingReviewQueue
```

Expected: compilation fails because `MeetingReviewQueue` does not exist.

- [ ] **Step 4: Implement queue state**

Replace the single published candidate with a queue.
Expose the current candidate and progress such as `"1 of 2"`.
On dismiss, remove only the current candidate.
On successful confirmation, remove only the confirmed candidate and keep the receipt associated with that result.
After closing the receipt, show the next queued candidate.

- [ ] **Step 5: Implement uncertainty presentation**

Preserve the existing two-column confirmation form and SUMI-E Ink styling.
Add:

- a small `"1 of 2"` queue label when multiple reviews remain;
- `"Needs review"` beside each uncertain field label;
- a restrained seal-red border or label for uncertain fields;
- confirm disabling when title is empty or required date/time is unresolved;
- accessible text that explains uncertainty without exposing model internals.

When the user edits an uncertain field, treat the edited field as reviewed for the current form.
Reconstruct the candidate without losing unchanged metadata or detector source.

- [ ] **Step 6: Build and run focused tests**

Run:

```bash
swift test --filter MeetingReviewQueue
swift build
```

Expected: tests and build pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/ZoidZeroApp/AppModel.swift Sources/ZoidZeroApp/MeetingCaptureView.swift Tests/ZoidZeroTests/MeetingReviewQueueTests.swift
git commit -m "feat: review uncertain meeting candidates"
```

### Task 6: Bilingual Evaluation, Privacy Verification, and UI Proof

**Files:**
- Create: `Tests/ZoidZeroTests/Fixtures/meeting-detection/evaluation.json`
- Create: `Tests/ZoidZeroTests/MeetingDetectionEvaluationTests.swift`
- Modify: `docs/superpowers/specs/2026-07-23-local-intelligent-meeting-detection-design.md` only if verified implementation details require factual corrections.

**Interfaces:**
- Consumes: the complete coordinator, parser, validator, queue, and app.
- Produces: permanent regression coverage and visual proof.

- [ ] **Step 1: Add the versioned bilingual evaluation fixture**

Include positive, ambiguous, and negative examples for:

- English, Arabic, and mixed language;
- `3 pm`, `3 p.m.`, `2.30`, `14:30`, Arabic digits, noon, and midnight;
- relative dates, weekdays, numeric dates, years, and explicit time zones;
- two meetings in one text;
- uncertain/incomplete wording;
- non-meeting uses of people, dates, and times;
- repeated screenshots and repeated mentions;
- daylight-saving and month/year boundaries.

Every fixture entry must contain the observation date, time zone, expected candidate count, expected local components, and expected uncertainty fields.

- [ ] **Step 2: Run the evaluation through fallback and coordinator seams**

Implement parameterized Swift Testing cases that load the JSON fixture.
The deterministic suite must run without Apple Intelligence.
The live on-device evaluation remains opt-in through `ZOID_RUN_LOCAL_MODEL_TESTS=1`.

Run:

```bash
swift test
npm test --prefix SafariExtension
```

Expected: all Swift and Safari Extension tests pass.

- [ ] **Step 3: Build the signed-form app artifact**

Run:

```bash
Scripts/build-app.sh
```

Expected: the macOS application builds successfully for the configured local signing or documented unsigned verification mode.

- [ ] **Step 4: Verify the real review flow in Codex's in-app Browser**

Launch the app through its supported local development path.
Use only Codex's built-in in-app Browser for navigation, inspection, and screenshots.
Feed or replay a fixture containing:

```text
Meeting with Mona tomorrow at 3 p.m.
Call Nour Friday at 2.30 pm.
```

Verify:

- one notification reports two meetings;
- two independent review cards are queued;
- the first resolves to 3:00 p.m.;
- the second resolves to 2:30 p.m.;
- uncertain fields are visibly marked;
- dismissing one leaves the other;
- no Calendar or Reminder item is created without confirmation.

- [ ] **Step 5: Capture proof**

Take an in-app Browser screenshot that visibly shows the queue count, a correct time, and an uncertainty marker.
Highlight the completed behavior without covering the relevant UI.
Record the absolute screenshot path in the completion report.

- [ ] **Step 6: Verify no accidental network path**

Search the changed implementation for URLSession, Network, HTTP clients, Private Cloud Compute entitlements, and model-provider dependencies.
Expected: the meeting-detection path contains none.

- [ ] **Step 7: Commit**

```bash
git add Tests/ZoidZeroTests/Fixtures/meeting-detection/evaluation.json Tests/ZoidZeroTests/MeetingDetectionEvaluationTests.swift
git commit -m "test: verify local meeting intelligence"
```

- [ ] **Step 8: Final verification**

Run:

```bash
swift test
swift build
git diff --check
git status --short
```

Expected: tests and build pass, no whitespace errors exist, and only pre-existing unrelated worktree changes remain.
