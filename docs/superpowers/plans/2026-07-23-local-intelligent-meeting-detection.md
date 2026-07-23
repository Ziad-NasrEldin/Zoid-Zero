# Local Intelligent Meeting Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make meeting detection reliably understand English, Arabic, and mixed-language meeting times while keeping all processing local.

**Architecture:** Keep the existing OCR, workflow, scheduling, and confirmation paths.
Add one Apple Foundation Models detector as the primary path, expand the existing parser as the fallback, and let both return the same array of meeting candidates.
Extend the existing app state and confirmation view for a small review queue instead of introducing separate validation, queue, diagnostics, or evaluation subsystems.

**Tech Stack:** Swift, SwiftUI, Swift Testing, Foundation Models, Foundation Calendar, Apple Vision, UserNotifications, and EventKit.

## Global Constraints

- Screenshots, OCR text, prompts, model output, and meeting candidates must remain on the Mac.
- Apple's on-device Foundation Models framework is the primary detector on supported Apple Intelligence-capable Macs.
- The deterministic parser is the automatic fallback when the model is unavailable, unsupported, fails, or returns unusable output.
- English, Arabic, and mixed-language text are supported.
- One screenshot may produce multiple independently reviewable candidates.
- Plausible candidates with uncertain fields are shown instead of silently discarded.
- Calendar events and Reminders are created only after explicit confirmation.
- Existing scheduling behavior and unrelated worktree changes must remain untouched.

## Scope Correction

The original plan was over-engineered for this codebase.
It proposed separate coordinator, temporal validator, queue, diagnostics, evaluation fixture, and storage-identity layers before the existing single-candidate path had been expanded.
This revision keeps the same approved behavior with one new production file, focused extensions to existing types, and tests placed beside the behavior they cover.

## Files

- Create `Sources/ZoidZeroInfrastructure/FoundationModelsMeetingDetector.swift`.
- Modify `Sources/ZoidZeroCore/MeetingDetector.swift`.
- Modify `Sources/ZoidZeroCore/MeetingModels.swift`.
- Modify `Sources/ZoidZeroCore/CaptureModels.swift`.
- Modify `Sources/ZoidZeroCore/MeetingCaptureWorkflow.swift`.
- Modify `Sources/ZoidZeroInfrastructure/ScreenAnalyzer.swift`.
- Modify `Sources/ZoidZeroInfrastructure/DesktopMeetingNotifier.swift`.
- Modify `Sources/ZoidZeroInfrastructure/ZoidRuntime.swift` only where the single candidate is forwarded.
- Modify `Sources/ZoidZeroApp/AppModel.swift`.
- Modify `Sources/ZoidZeroApp/MeetingCaptureView.swift`.
- Modify `Package.swift` and `Scripts/build-app.sh` only as required to compile Foundation Models.
- Extend existing test files under `Tests/ZoidZeroTests`.

### Task 1: Expand the Existing Parser and Candidate Model

**Files:**

- Modify: `Sources/ZoidZeroCore/MeetingDetector.swift`
- Modify: `Sources/ZoidZeroCore/MeetingModels.swift`
- Test: `Tests/ZoidZeroTests/MeetingDetectorTests.swift`

- [ ] **Step 1: Add failing parser regressions**

Add table-driven tests for:

- `Meeting tomorrow at 3 p.m.` resolving to 15:00.
- `Meeting tomorrow at 2.30 pm` resolving to 14:30.
- `اجتماع بكرة الساعة ٣:٤٥ م` resolving to 15:45.
- English, Arabic, and mixed-language meeting intent.
- Two separate meetings in one input returning two candidates in source order.
- `around 3`, `حوالي ٣`, or a missing optional field returning a candidate marked for review.
- Ordinary clock or date mentions without meeting intent returning no candidate.
- Impossible dates and times returning no candidate.

Run:

```bash
swift test --filter MeetingDetector
```

Expected: the new dotted-time, multiple-candidate, and uncertainty cases fail against the current first-match parser.

- [ ] **Step 2: Make the minimum shared model change**

Add a small Codable field enum for `title`, `person`, `date`, `time`, `timeZone`, and `duration`.
Add optional detector source and uncertain-field properties to `MeetingCandidate`.
Keep the existing initializer source-compatible with defaults.
Use optional properties so older locally stored candidates continue decoding without a custom storage migration.

- [ ] **Step 3: Expand `MeetingDetector` instead of replacing it with a parser subsystem**

Change its public detection result from one optional candidate to `[MeetingCandidate]`.
Normalize Arabic digits and common punctuation before matching.
Accept `am`, `pm`, `a.m.`, `p.m.`, Arabic meridiems, `:`, `.`, and 24-hour time.
Support today, tomorrow, weekdays, common numeric dates, and their Arabic equivalents.
Split input into meeting-like spans and return every valid match.
Resolve dates with the injected `Calendar`, reject impossible components, and mark ambiguous or defaulted fields as uncertain.
Keep a compatibility wrapper only if an existing caller needs it during the same task.

- [ ] **Step 4: Verify and commit**

Run:

```bash
swift test --filter MeetingDetector
git diff --check
```

Expected: all parser regressions pass and there are no whitespace errors.

Commit:

```bash
git add Sources/ZoidZeroCore/MeetingDetector.swift Sources/ZoidZeroCore/MeetingModels.swift Tests/ZoidZeroTests/MeetingDetectorTests.swift
git commit -m "feat: improve bilingual meeting parsing"
```

### Task 2: Add Apple On-Device Detection With Direct Fallback

**Files:**

- Create: `Sources/ZoidZeroInfrastructure/FoundationModelsMeetingDetector.swift`
- Modify: `Sources/ZoidZeroInfrastructure/ScreenAnalyzer.swift`
- Modify: `Package.swift`
- Modify: `Scripts/build-app.sh`
- Test: `Tests/ZoidZeroTests/ChangedScreenPipelineTests.swift`

- [ ] **Step 1: Add failing primary and fallback tests**

Introduce one small detector protocol at the existing analyzer seam:

```swift
public protocol MeetingDetecting: Sendable {
  func detectMeetings(
    text: String,
    personHint: String,
    observedAt: Date,
    fingerprint: String
  ) async throws -> [MeetingCandidate]
}
```

Use test doubles to prove:

- Valid primary results are returned without calling the fallback.
- Model unavailable, unsupported, failed, and unusable-result cases call the fallback.
- A successful primary result with no meetings does not create false fallback candidates.
- Two primary candidates remain two candidates.
- OCR text and context are passed only to local detector objects.

Run:

```bash
swift test --filter ChangedScreenPipeline
```

Expected: the tests fail because `ScreenAnalyzer` currently owns a synchronous parser and one optional candidate.

- [ ] **Step 2: Implement the Foundation Models adapter**

Use `SystemLanguageModel.default` and `LanguageModelSession`.
Use guided generation to return a bounded structure containing zero or more meetings.
Include original date and time expressions plus uncertainty flags so Swift code, not model prose, controls final candidate construction.
Prompt for English, Arabic, and mixed-language extraction without tools or side effects.
Check model availability and locale support before inference.
Throw a local unavailable or unusable-output error for the analyzer to handle.
Do not add a generic model-provider abstraction, diagnostics store, timeout service, or third-party model integration.

- [ ] **Step 3: Wire primary then fallback in `ScreenAnalyzer`**

Run the Foundation Models detector first.
Use the improved `MeetingDetector` only when the primary cannot run or returns unusable output.
Treat a successful empty model response as no detected meeting.
Return all candidates in `ScreenAnalysisResult`.
Raise the macOS deployment target only to the minimum version required by the installed Foundation Models SDK.

- [ ] **Step 4: Verify and commit**

Run:

```bash
swift test --filter ChangedScreenPipeline
swift build
git diff --check
```

Expected: the detector-seam tests and package build pass.

Commit:

```bash
git add Package.swift Scripts/build-app.sh Sources/ZoidZeroInfrastructure/FoundationModelsMeetingDetector.swift Sources/ZoidZeroInfrastructure/ScreenAnalyzer.swift Tests/ZoidZeroTests/ChangedScreenPipelineTests.swift
git commit -m "feat: add local foundation model meeting detection"
```

### Task 3: Carry Multiple Candidates Into the Existing Review Screen

**Files:**

- Modify: `Sources/ZoidZeroCore/CaptureModels.swift`
- Modify: `Sources/ZoidZeroCore/MeetingCaptureWorkflow.swift`
- Modify: `Sources/ZoidZeroInfrastructure/DesktopMeetingNotifier.swift`
- Modify: `Sources/ZoidZeroInfrastructure/ZoidRuntime.swift`
- Modify: `Sources/ZoidZeroApp/AppModel.swift`
- Modify: `Sources/ZoidZeroApp/MeetingCaptureView.swift`
- Test: `Tests/ZoidZeroTests/MeetingCaptureWorkflowTests.swift`
- Test: `Tests/ZoidZeroTests/ZoidRuntimeTests.swift`

- [ ] **Step 1: Add failing batch and review-flow tests**

Verify:

- One analysis carries two candidates.
- The workflow accepts both candidates and sends one summary notification.
- Repeating the same candidate fingerprint does not add another review item.
- Confirming or dismissing one candidate leaves the other available.
- A candidate with uncertain required date or time cannot be confirmed until edited.
- Scheduling is called only for the candidate explicitly confirmed by the user.

Run:

```bash
swift test --filter MeetingCaptureWorkflow
swift test --filter ZoidRuntime
```

Expected: the new tests fail at the current single-candidate interfaces.

- [ ] **Step 2: Convert the existing path from one candidate to an array**

Change `ScreenAnalysisResult.candidate` to `candidates`.
Change the workflow handler and notifier to accept candidate arrays.
Process each candidate through the existing fingerprint store and record store.
Send one notification with singular or plural copy based on the accepted count.
Do not add a second deduplication database or normalized identity store in this release.

- [ ] **Step 3: Use a simple queue in `AppModel`**

Store pending candidates in an array.
Append accepted candidates whose IDs are not already pending.
Expose the first item as the candidate under review.
Remove only that item after dismissal or successful confirmation.
Keep the existing explicit scheduling call unchanged.
Do not introduce a separate queue actor or persistence format unless concurrency tests prove the array unsafe.

- [ ] **Step 4: Update the existing confirmation view**

Read `/Users/ziadnasreldin/.agents/skills/emil-design-eng/SKILL.md` before the UI edit.
Preserve the existing SUMI-E Ink layout.
Show progress such as `1 of 2`.
Mark uncertain fields with clear `Needs review` text.
Keep every field editable.
Disable confirmation while a required field remains unresolved or invalid.
Let the user confirm or dismiss each candidate independently.

- [ ] **Step 5: Verify and commit**

Run:

```bash
swift test --filter MeetingCaptureWorkflow
swift test --filter ZoidRuntime
swift build
git diff --check
```

Expected: batch flow, independent review, explicit confirmation, and build checks pass.

Commit:

```bash
git add Sources/ZoidZeroCore/CaptureModels.swift Sources/ZoidZeroCore/MeetingCaptureWorkflow.swift Sources/ZoidZeroInfrastructure/DesktopMeetingNotifier.swift Sources/ZoidZeroInfrastructure/ZoidRuntime.swift Sources/ZoidZeroApp/AppModel.swift Sources/ZoidZeroApp/MeetingCaptureView.swift Tests/ZoidZeroTests/MeetingCaptureWorkflowTests.swift Tests/ZoidZeroTests/ZoidRuntimeTests.swift
git commit -m "feat: review multiple meeting candidates"
```

### Task 4: Complete Regression Coverage and Real UI Proof

**Files:**

- Modify existing meeting-related tests under `Tests/ZoidZeroTests`.
- Do not add a separate JSON evaluation framework for this release.

- [ ] **Step 1: Complete table-driven coverage**

Keep deterministic cases in the normal Swift test suite.
Cover English, Arabic, mixed language, punctuation variants, Arabic digits, relative dates, multiple meetings, uncertainty, false positives, noon, midnight, and date boundaries.
Test Foundation Models behavior through the detector seam with recorded structured results.
Do not assert live model wording in the normal suite because model output is not deterministic.

- [ ] **Step 2: Run the complete automated checks**

Run:

```bash
swift test
swift build
npm test --prefix SafariExtension
Scripts/build-app.sh
git diff --check
```

Expected: all tests and builds pass with no whitespace errors.

- [ ] **Step 3: Verify the real supported-Mac flow**

Use a real capture containing:

```text
Meeting with Mona tomorrow at 3 p.m.
Call Nour Friday at 2.30 pm.
```

Verify:

- The primary on-device model is used when Apple Intelligence is available.
- Disabling or making the model unavailable activates the parser fallback.
- Both meetings appear independently with 15:00 and 14:30 local times.
- Uncertain fields are visibly marked and editable.
- Dismissing one candidate leaves the other.
- No Calendar event or Reminder is created before confirmation.

- [ ] **Step 4: Capture UI proof**

Use only Codex's built-in in-app Browser for UI QA and screenshots.
Capture a screenshot showing the queue count, a correct parsed time, and an uncertainty marker.
Report the absolute screenshot path with the implementation result.

- [ ] **Step 5: Final privacy check**

Inspect the changed meeting-detection path for network clients, remote model providers, and Private Cloud Compute use.
Expected: no screenshot or recognized text can leave the Mac through this feature.

- [ ] **Step 6: Commit any test-only additions**

```bash
git add Tests/ZoidZeroTests
git commit -m "test: cover local intelligent meeting detection"
```

## Completion Criteria

- `3 p.m.`, `2.30`, Arabic digits, and agreed bilingual expressions resolve correctly.
- Apple Foundation Models is the primary local detector on supported Macs.
- The improved bilingual parser activates automatically as fallback.
- Multiple candidates are independently reviewable.
- Uncertain candidates remain visible and editable.
- Scheduling still requires explicit confirmation.
- Automated tests, app build, privacy inspection, and UI screenshot proof are complete.
