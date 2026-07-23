# Integrated Capture and Time Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> This task must be executed inline in the visible task because the approved request explicitly forbids hidden subagents.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one signed Zoid 0 macOS application that owns bounded local screen capture, local meeting detection, categorized application and Safari website time tracking, confirmation, and safe Calendar and Reminder creation.

**Architecture:** Keep policy and deterministic state machines in `ZoidZeroCore`, put macOS framework integrations and local persistence in `ZoidZeroInfrastructure`, and let `AppModel` own the main-process lifecycle.
The capture coordinator samples the active display, performs a cheap in-memory fingerprint comparison, debounces meaningful changes, and feeds a latest-only OCR processor that persists only analyzed images.
The application activity tracker uses workspace and session notifications independently of capture, closes non-overlapping intervals at every state transition, and exposes daily application totals.
An embedded Safari Web Extension reports only normalized active-tab domains through Apple's local extension messaging boundary.
The native tracker reconciles website intervals with Safari application intervals so the same time is never counted twice.

**Tech Stack:** Swift 6, SwiftUI, AppKit, SafariServices, WebExtensions, ScreenCaptureKit, Vision, CoreGraphics, CryptoKit, EventKit, UserNotifications, Swift Testing, JavaScript for the extension background script, and a signed macOS application bundle.

## Global Constraints

- Use one user-installed application bundle and the stable `com.ziadnasreldin.zoidzero` main-app bundle identifier.
- Keep capture, OCR, meeting detection, application tracking, storage, and scheduling in the main process.
- Allow only the embedded Safari Web Extension to run in Safari's extension process.
- Do not add a standalone helper, daemon, login item, or separately installed application.
- Start capture automatically at launch when Screen Recording permission is available.
- Keep capture and time tracking running after the main window closes.
- Explicit Quit must cancel capture, OCR, detection, and tracking, finalize active writes, and terminate.
- Explicit Quit must clear the extension tracking-session marker so Safari records nothing while Zoid 0 is not running.
- Store capture output under `~/Library/Application Support/ZoidZero/Screenwatch/days/YYYY-MM-DD/`.
- Sample every five seconds while active and pause after 90 seconds of inactivity.
- Debounce meaningful changes and run accurate local OCR no more than once every 15 seconds.
- Keep only the newest queued OCR item while recognition is busy.
- Inspect changed screens from every application.
- Use runtime-supported English and Arabic Vision recognition languages only.
- Never use remote OCR or any remote screen-processing service.
- Report daily category totals with filtered application and Safari-domain contributors.
- Store only normalized domains for website activity.
- Never store full URLs, paths, queries, fragments, page titles, page contents, or inactive-tab history.
- Replace matching Safari application intervals with website intervals instead of double-counting them.
- Fall back to generic Safari time whenever website permission or active-domain data is unavailable.
- Never schedule without explicit confirmation.
- Never add attendees or send invitations, messages, emails, or any client communication.
- Do not add launch-at-login, standalone helpers, daemons, history management, deletion tools, window-title reports, per-page reports, non-Safari browser tracking, or remote services.

---

### Task 1: Application activity state machine and daily totals

**Files:**
- Create: `Sources/ZoidZeroCore/ApplicationActivity.swift`
- Create: `Sources/ZoidZeroInfrastructure/ApplicationActivityStore.swift`
- Create: `Sources/ZoidZeroInfrastructure/ApplicationActivityTracker.swift`
- Create: `Tests/ZoidZeroTests/ApplicationActivityTrackerTests.swift`

**Interfaces:**
- Produces: `ApplicationIdentity`, `ApplicationActivityInterval`, `DailyApplicationTotal`, and `ApplicationActivityRecording`.
- Produces: `ApplicationActivityTracker.start()`, `transition(to:at:)`, `pause(at:)`, `resume(at:)`, `dailyTotals(for:)`, and `stop(at:)`.
- Consumes: `NSWorkspace` activation, sleep, wake, lock, unlock, session resign, and session become-active notifications.

- [ ] **Step 1: Write failing deterministic state-machine tests**

```swift
@Test("application switches create non-overlapping intervals")
func applicationSwitchesCreateIntervals() async throws {
    let store = ActivityStoreSpy()
    let tracker = ApplicationActivityTracker(store: store, now: { start })
    await tracker.transition(to: safari, at: start)
    await tracker.transition(to: mail, at: start.addingTimeInterval(30))
    await tracker.stop(at: start.addingTimeInterval(50))
    #expect(await store.intervals.map(\.duration) == [30, 20])
}
```

Add separate tests proving idle, sleep, lock, and inactive-session pauses close the active interval and do not attribute paused time.
Add a test proving daily totals group only by bundle identifier and display name.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter ApplicationActivityTrackerTests`
Expected: compilation fails because the activity types and tracker do not exist.

- [ ] **Step 3: Implement the minimal state machine and JSONL-backed store**

Use one actor-owned active interval.
Every app switch or pause closes the current interval once.
Resume starts from the current frontmost application.
Persist complete intervals as newline-delimited JSON and compute totals from intervals intersecting the requested local calendar day.

- [ ] **Step 4: Wire macOS activity and session events**

Subscribe to `NSWorkspace.didActivateApplicationNotification`, sleep, wake, session resign, and session become-active.
Subscribe to distributed screen lock and unlock notifications.
Use `CGEventSource.secondsSinceLastEventType` on a lightweight timer to pause after 90 seconds and resume after activity.
Remove observers and finish the active interval in `stop`.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter ApplicationActivityTrackerTests`
Expected: all activity tests pass.

Run: `swift test`
Expected: all existing and new tests pass with no failures.

---

### Task 1A: Categories and Safari website activity

**Files:**
- Create: `Sources/ZoidZeroCore/ActivityCategory.swift`
- Create: `Sources/ZoidZeroCore/WebsiteActivity.swift`
- Create: `Sources/ZoidZeroInfrastructure/WebsiteActivityTracker.swift`
- Create: `Sources/ZoidZeroInfrastructure/SafariActivityInbox.swift`
- Modify: `Sources/ZoidZeroInfrastructure/ZoidLocalStore.swift`
- Modify: `Sources/ZoidZeroInfrastructure/ZoidRuntime.swift`
- Create: `SafariExtension/Resources/manifest.json`
- Create: `SafariExtension/Resources/background.js`
- Create: `SafariExtension/SafariWebExtensionHandler.swift`
- Create: `Tests/ZoidZeroTests/ActivityCategorizationTests.swift`
- Create: `Tests/ZoidZeroTests/WebsiteActivityTrackerTests.swift`
- Create: a host Xcode project containing the existing macOS app target and embedded Safari Web Extension target
- Modify: `Scripts/build-app.sh`

**Interfaces:**
- Produces: `ActivityCategory`, `ActivitySubject`, `CategoryAssignment`, `DailyCategoryTotal`, and categorized contributors.
- Produces: `WebsiteIdentity`, `WebsiteActivityInterval`, and `WebsiteActivityTracker`.
- Produces: a local app-group inbox for extension events containing only normalized domains and timestamps.
- Consumes: active Safari tab changes, Safari foreground application intervals, default assignments, and user overrides.

- [ ] **Step 1: Write failing categorization and reconciliation tests**

Test the fixed initial categories: Work, Communication, Social, Gaming, Media, Utilities, Browser, and Uncategorized.
Test that assignments use application bundle identifiers and normalized domains rather than display labels.
Test that a user assignment overrides a default assignment.
Test that unknown applications and domains remain Uncategorized.
Test registrable-domain normalization against subdomains, multi-part public suffixes, IP addresses, localhost, and malformed input.
Test that a website interval replaces only the overlapping part of its Safari application interval.
Test that unavailable website data leaves the interval attributed to Safari in Browser.
Test that category totals exactly equal their visible contributors.
Test that extension events are rejected when the main-app tracking-session marker is missing or expired.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter ActivityCategorizationTests`
Expected: compilation fails because category types do not exist.

Run: `swift test --filter WebsiteActivityTrackerTests`
Expected: compilation fails because website activity types do not exist.

- [ ] **Step 3: Implement minimal category policy and persistence**

Use a single assignment model that accepts either an application bundle identifier or a normalized domain.
Keep defaults deterministic and small.
Persist user assignments separately so a later default update cannot overwrite them.
Do not infer categories from screenshots, OCR, page contents, or page titles.

- [ ] **Step 4: Create the embedded Safari Web Extension**

Add one Safari Web Extension target embedded in the signed Zoid 0 application.
Keep `com.ziadnasreldin.zoidzero` as the main application identifier and use a stable child identifier for the extension.
Use Safari tab activation, tab URL update, and window-focus events to identify the active tab.
Normalize the URL to its registrable domain inside the extension before crossing the native messaging boundary.
Use a bundled, deterministic public-suffix implementation so domains such as `example.co.uk` normalize correctly without network access.
Never transmit or persist the full URL, path, query, fragment, page title, page content, or inactive-tab history.
Use Apple's native extension messaging and an app group shared only by the Zoid 0 app and its extension.
Require a short-lived main-app tracking-session marker before accepting or writing an extension event.
Request website permission honestly and explain that full coverage requires access to all websites.

- [ ] **Step 5: Reconcile website and Safari application intervals**

Accept website intervals only while Safari is the foreground application and the Mac is not paused for idle, sleep, lock, or inactive session.
Split generic Safari intervals around known website intervals.
Attribute unmatched Safari time to Browser.
Deduplicate repeated extension messages and close the current website interval on tab change, Safari deactivation, pause, permission loss, or shutdown.

- [ ] **Step 6: Establish the signed extension build**

Keep Swift Package Manager as the deterministic core and test boundary.
Add an Xcode host project for the app and embedded Safari Web Extension because Safari owns the extension lifecycle and signing.
Update `Scripts/build-app.sh` to produce one user-installed `.build/Zoid 0.app` containing the signed extension.
Verify both the main app and embedded extension signatures and stable identifiers.

- [ ] **Step 7: Run focused and full tests**

Run: `swift test --filter ActivityCategorizationTests`
Expected: all categorization tests pass.

Run: `swift test --filter WebsiteActivityTrackerTests`
Expected: all domain privacy, interval, fallback, and no-double-counting tests pass.

Run: `swift test`
Expected: all tests pass.

---

### Task 2: Bounded changed-screen analysis pipeline

**Files:**
- Create: `Sources/ZoidZeroCore/CaptureModels.swift`
- Create: `Sources/ZoidZeroCore/ChangedScreenPipeline.swift`
- Create: `Tests/ZoidZeroTests/ChangedScreenPipelineTests.swift`

**Interfaces:**
- Produces: `CaptureHealth`, `CapturedScreen`, `VisualFingerprint`, `ScreenAnalysisResult`, and `ChangedScreenPipeline`.
- Produces: `submit(_:)`, `finishCurrentWork()`, and an async result callback.
- Consumes: a clock, fingerprint comparator, OCR closure, and analysis callback injected for deterministic tests.

- [ ] **Step 1: Write failing pipeline policy tests**

```swift
@Test("unchanged screens never run OCR")
func unchangedScreensSkipOCR() async {
    let harness = PipelineHarness()
    await harness.pipeline.submit(harness.screen(fingerprint: .same))
    await harness.pipeline.submit(harness.screen(fingerprint: .same))
    #expect(await harness.ocrInputs.count == 1)
}
```

Add tests proving OCR starts no more than once per 15 seconds, a busy pipeline retains only the newest item, and screens from non-WhatsApp applications are analyzed.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter ChangedScreenPipelineTests`
Expected: compilation fails because the pipeline types do not exist.

- [ ] **Step 3: Implement the bounded actor**

Compare downscaled fingerprints before persistence or OCR.
Debounce accepted changes.
When OCR is busy, replace the queued item instead of appending.
Respect the 15-second minimum OCR start interval.
Continue after an individual OCR failure and emit honest health changes.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter ChangedScreenPipelineTests`
Expected: all pipeline policy tests pass.

Run: `swift test`
Expected: all tests pass.

---

### Task 3: Internal ScreenCaptureKit service, local Vision OCR, and capture storage

**Files:**
- Create: `Sources/ZoidZeroInfrastructure/ScreenCaptureService.swift`
- Create: `Sources/ZoidZeroInfrastructure/ScreenCaptureStorage.swift`
- Modify: `Sources/ZoidZeroInfrastructure/VisionTextRecognizer.swift`
- Replace: `Sources/ZoidZeroInfrastructure/ScreenwatchSource.swift`
- Create: `Tests/ZoidZeroTests/ScreenCaptureStorageTests.swift`
- Create: `Tests/ZoidZeroTests/VisionLanguageSelectionTests.swift`

**Interfaces:**
- Produces: `ScreenCapturing.start()`, `stop()`, `healthUpdates`, and analyzed-screen callbacks.
- Produces: `ScreenCaptureStorage.persistAnalyzedScreen(_:)` and Screenwatch-compatible JSONL records.
- Produces: `VisionTextRecognizer.supportedRecognitionLanguages()` and in-memory `recognizeText(in:)`.
- Consumes: `SCScreenshotManager`, the main display, active app context, and the bounded core pipeline.

- [ ] **Step 1: Write failing storage and language-selection tests**

Test the exact Application Support path suffix.
Test that JSONL records contain timestamp, epoch, application, window, and image presence fields.
Test that Arabic is requested only when present in Vision's runtime-supported language list and English falls back safely.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter ScreenCaptureStorageTests`
Expected: compilation fails because capture storage does not exist.

Run: `swift test --filter VisionLanguageSelectionTests`
Expected: the language-selection API is missing.

- [ ] **Step 3: Implement ScreenCaptureKit sampling**

Preflight Screen Recording permission before starting.
Request it only when authorization is undetermined for this app session.
Capture the active display every five seconds while activity is below 90 seconds.
Downscale to a small grayscale fingerprint in memory and submit meaningful changes to the pipeline.
Do not launch or inspect any external Screenwatch executable or `~/screenwatch`.

- [ ] **Step 4: Implement retention and metadata**

Write analyzed JPEG images and Screenwatch-compatible `log.jsonl` records under the ZoidZero Application Support directory.
Delete temporary image data for rejected, superseded, or failed queued samples.
Synchronize metadata writes before reporting completion.

- [ ] **Step 5: Implement runtime-safe local OCR**

Use `VNRecognizeTextRequest` with `.accurate` recognition and language correction.
Query supported languages at runtime.
Select supported English and Arabic language identifiers without assuming `ar-SA` exists.
Never add networking dependencies.

- [ ] **Step 6: Run focused and full tests**

Run: `swift test --filter ScreenCapture`
Expected: capture policy and storage tests pass.

Run: `swift test --filter VisionLanguageSelectionTests`
Expected: language selection tests pass.

Run: `swift test`
Expected: all tests pass.

---

### Task 4: One-process application lifecycle and permission-safe orchestration

**Files:**
- Create: `Sources/ZoidZeroInfrastructure/ZoidRuntime.swift`
- Modify: `Sources/ZoidZeroApp/AppModel.swift`
- Modify: `Sources/ZoidZeroApp/ZoidZeroApp.swift`
- Modify: `Sources/ZoidZeroInfrastructure/DesktopMeetingNotifier.swift`
- Modify: `Sources/ZoidZeroInfrastructure/AppleSchedulingService.swift`
- Modify: `Resources/Info.plist`
- Create: `Tests/ZoidZeroTests/ZoidRuntimeTests.swift`

**Interfaces:**
- Produces: `ZoidRuntime.start()`, `stop()`, `captureHealth`, `dailyTotals`, and candidate callbacks.
- Consumes: capture, activity tracker, detector, notifier, fingerprint store, and scheduling service.

- [ ] **Step 1: Write failing lifecycle tests**

Test that launch starts capture and tracking.
Test that a window-close signal does not stop either service.
Test that explicit stop cancels capture and finalizes the active activity interval.
Test that a changed-screen OCR result flows through detection and produces exactly one editable candidate.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `swift test --filter ZoidRuntimeTests`
Expected: compilation fails because `ZoidRuntime` does not exist.

- [ ] **Step 3: Implement runtime orchestration**

Create long-lived capture and activity services once in `AppModel`.
Start them from application launch, not from a window `.task`.
Deliver candidates to the existing notification and editable confirmation flow.
Keep the window close action independent from runtime stop.

- [ ] **Step 4: Implement explicit Quit finalization**

Use an application delegate termination hook to await runtime shutdown before replying to AppKit termination.
Cancel capture and OCR work.
Stop observers and finalize the activity interval and pending writes.
Then allow the process to exit.

- [ ] **Step 5: Harden permission behavior**

Keep the stable bundle identifier unchanged.
Add the Screen Recording usage description where supported.
Request notification permission once per authorization state rather than on every launch after denial.
Keep Calendar and Reminder requests inside the explicit confirm path only.
Expose an Open System Settings action for denied Screen Recording access.

- [ ] **Step 6: Run focused and full tests**

Run: `swift test --filter ZoidRuntimeTests`
Expected: all lifecycle and integration tests pass.

Run: `swift test`
Expected: all tests pass.

---

### Task 5: SUMI-E health and categorized daily activity interface

**Files:**
- Modify: `Sources/ZoidZeroApp/MeetingCaptureView.swift`
- Modify: `Sources/ZoidZeroApp/SumiTheme.swift`
- Modify: `Sources/ZoidZeroApp/AppModel.swift`

**Interfaces:**
- Consumes: `CaptureHealth`, daily category totals, filtered contributors, Safari extension state, category assignments, candidate, receipt, and settings actions.
- Produces: visible Monitoring, Analyzing changed screen, Paused while idle, Screen Recording permission needed, and Capture error states.

- [ ] **Step 1: Add honest health-state rendering**

Replace the obsolete external Screenwatch copy.
Show the exact current capture state and never show Monitoring when capture is unavailable.
Show a direct Open System Settings action only for the permission-needed state.

- [ ] **Step 2: Add category-first daily totals**

Rename the panel to `Where your time went`.
Show the selected day's total, a compact proportional category bar, and category rows with durations.
Add visible All, Work, Communication, Social, Gaming, Media, Utilities, Browser, and Uncategorized filters.
Show application names and normalized domains as contributors under the selected category.
Show each contributor's assigned category and duration.
Add previous-day, today, and next-day navigation without introducing a full history manager.
Do not show full URLs, page titles, window titles, screenshot history, or deletion controls.
Use the existing paper, ink, seal-red, serif, accessible light and dark appearance, and reduced-motion behavior.

- [ ] **Step 3: Add category assignment and Safari extension states**

Provide a visible `Categorize apps & websites` action.
Allow direct reassignment from each contributor row.
Show the number of Uncategorized contributors without interrupting tracking.
Show Safari website tracking as On, Permission needed, Extension disabled, or Unavailable.
When website data is unavailable, explain that time remains under Safari in Browser.
Never imply that generic Safari time represents a known website.

- [ ] **Step 4: Review visible interaction details**

Keep confirmation fields editable and prominent.
Keep the no-attendees safety statement visible next to Confirm.
Use restrained press feedback only and do not add decorative recurring animations.

- [ ] **Step 5: Build and inspect the interface**

Run: `swift build`
Expected: the app compiles with no errors.

Run the signed application and capture a proof screenshot if the built-in Browser can capture the native window.
If the built-in Browser cannot capture a native macOS window, record that exact limitation and do not substitute Chrome or another browser.

---

### Task 6: Release verification and full diff audit

**Files:**
- Modify only files required to correct verification findings.

**Interfaces:**
- Consumes the complete implementation.
- Produces a signed release app and an evidence-backed verification report.

- [ ] **Step 1: Run focused integration and full tests**

Run: `swift test --filter ZoidRuntimeTests`
Expected: changed-screen to editable-candidate lifecycle tests pass.

Run: `swift test`
Expected: all tests pass with zero failures.

- [ ] **Step 2: Build and validate the signed release bundle**

Run: `Scripts/build-app.sh release`
Expected: `.build/Zoid 0.app` is created.

Run: `codesign --verify --deep --strict --verbose=2 '.build/Zoid 0.app'`
Expected: the main app and embedded Safari Web Extension verify successfully.

Run: `codesign -d --entitlements :- '.build/Zoid 0.app'`
Expected: the main-app signature is readable and keeps the stable identity.

Inspect the embedded extension's identifier and entitlements.
Expected: it uses the approved stable child identifier and shares only the Zoid 0 app group.

Run: `plutil -lint '.build/Zoid 0.app/Contents/Info.plist'`
Expected: `OK`.

- [ ] **Step 3: Run lifecycle smoke checks that do not require private user data**

Launch the signed app.
Verify one main Zoid 0 process and no external Screenwatch child process.
Allow Safari to run only the embedded extension process while Safari website tracking is enabled.
Close the main window and verify the process remains running.
Choose explicit Quit and verify the process exits and capture metadata handles close.
Do not create a real Calendar event or Reminder without the user's explicit confirmation.

- [ ] **Step 4: Run Safari website smoke checks**

Enable the bundled extension and grant access to two harmless test domains.
Switch between those active Safari tabs and verify separate normalized-domain intervals.
Verify the stored records contain no full URL, path, query, fragment, or page title.
Verify the matching time is not also counted under generic Safari.
Revoke website access and verify later time falls back to Safari in Browser without stopping application tracking.

- [ ] **Step 5: Audit the entire diff**

Read every changed file completely.
Check privacy, permission identity, extension permissions, domain normalization, no-double-counting, category overrides, scheduling safety, no-attendee behavior, lifecycle cancellation, interval overlap, idle handling, bounded OCR queue size, OCR cadence, capture retention, and out-of-scope exclusions.
Correct every confirmed issue and rerun the relevant verification.

- [ ] **Step 6: Report exact verification boundaries**

Separate automated verification from signed runtime checks.
List any remaining checks requiring the user's Screen Recording, Safari website, notification, Calendar, or Reminders permission and explicit interaction.
