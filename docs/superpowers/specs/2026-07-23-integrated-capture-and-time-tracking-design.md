# Zoid 0 Integrated Capture and Time Tracking Design

Status: approved

Website tracking amendment approved: 2026-07-23

## Purpose

Zoid 0 will become one native macOS application that owns application and Safari website time tracking, screen observation, local meeting detection, confirmation, Calendar creation, and Reminder creation.
The existing external Screenwatch installation will no longer be required.
Screenwatch will become an internal capture service inside the Zoid 0 process.
Safari website tracking will use an embedded Safari Web Extension that communicates only with Zoid 0 on the local Mac.

## Product Boundary

Zoid 0 will use one user-installed application bundle and one stable main-application bundle identifier.
Capture, OCR, meeting detection, application tracking, storage, and scheduling will remain in the main Zoid 0 process.
The application bundle may contain one Safari Web Extension that Safari runs in its extension process.
The extension is not a standalone helper, daemon, login item, or independently installed application.
Closing the main window will leave Zoid 0 running in the background.
Choosing Quit Zoid 0 will stop capture and time tracking, safely finish active writes, and terminate the process.
Zoid 0 will not install or launch a separate helper, daemon, or Screenwatch executable.
Zoid 0 will never send a WhatsApp message, email, Calendar invitation, attendee invitation, or any other communication.
Calendar and Reminder changes will still require explicit user confirmation.

## Permissions

Zoid 0 will request Screen Recording permission when capture first starts.
Zoid 0 will request notification permission before delivering meeting notifications.
Zoid 0 will request Calendar and Reminders permission only when the user confirms a meeting.
macOS will retain these permissions for Zoid 0's stable signed bundle identity unless the user revokes them or the application identity changes.
When Screen Recording permission is denied, Zoid 0 will show an honest blocked state and an Open System Settings action.
Zoid 0 will not repeatedly trigger a system permission prompt after denial.
Safari website tracking will remain off until the user enables the bundled extension and grants website access in Safari.
Zoid 0 will explain that full website coverage requires access to all websites while allowing the user to grant access to fewer websites.
Denied or missing Safari access will not interrupt application-level tracking.

## Application Time Tracking

Application time tracking will not depend on screenshots or OCR.
Zoid 0 will subscribe to macOS `NSWorkspace` application-activation events.
Each activity interval will record the application's bundle identifier, display name, start time, end time, and duration.
The tracker will pause time attribution while the Mac is idle, locked, asleep, or the user session is inactive.
The first version will report daily totals grouped into Work, Communication, Social, Gaming, Media, Utilities, Browser, and Uncategorized.
Application assignments will use the stable application bundle identifier.
Known applications may receive a default category.
Unknown applications will remain Uncategorized until the user assigns them.
User assignments will always override defaults.
The interface will show category totals first and allow category filters to reveal the contributing applications and websites.
Document names and individual window-title totals are not required for the first version.

## Safari Website Time Tracking

Zoid 0 will include an embedded Safari Web Extension for website-level time attribution.
The extension will observe only the active Safari tab while Safari is the foreground application.
It will reduce the active page address to its registrable domain before sending an activity change to the native extension boundary.
For example, a YouTube watch address will become `youtube.com`.
The full URL, path, query string, fragment, page title, page content, and inactive-tab history will not be sent to or stored by Zoid 0.
Website identification will not use screenshots or OCR.

Each website activity interval will record the browser identity, normalized domain, start time, end time, and duration.
Domain assignments will use the normalized domain.
Known domains may receive a default category.
Unknown domains will remain Uncategorized until the user assigns them.
User assignments will always override defaults.

Website intervals will replace the matching portion of generic Safari application time rather than being added to it.
Time for which the active domain is unavailable will remain attributed to Safari in the Browser category.
The system will never count the same interval as both Safari application time and website time.

The extension and native app will communicate locally through Apple's supported Safari extension messaging boundary.
No website activity will leave the Mac.
The main app will publish a short-lived tracking-session marker that is refreshed only while Zoid 0 is running.
The extension will discard activity when that marker is missing or expired, and explicit Quit will clear it.
Disabling the extension or revoking its website permission will immediately fall back to application-level Safari tracking.
Website tracking for browsers other than Safari is not included in this version.

## Internal Screenwatch Capture

The internal capture service will use Apple's ScreenCaptureKit.
It will start automatically when Zoid 0 launches and Screen Recording permission is available.
It will observe the active display while Zoid 0 remains open or backgrounded.
It will stop only when the process quits or capture encounters a permission or system failure.

Capture data will be stored under:

`~/Library/Application Support/ZoidZero/Screenwatch/days/YYYY-MM-DD/`

Zoid 0 will own this internal data.
The capture service will append Screenwatch-compatible JSONL metadata and use timestamped image files.
The application will not require or modify `~/screenwatch`.

## Resource Control

Zoid 0 will separate cheap screen sampling from expensive text recognition.
It will sample the screen every five seconds while the user is active.
It will skip sampling after 90 seconds of user inactivity.
Each sample will create a small in-memory visual fingerprint.
Screens that have not changed meaningfully will be discarded without being saved or recognized.
When a meaningful change occurs, Zoid 0 will briefly debounce the screen to avoid analyzing half-rendered interfaces.
Accurate OCR will run no more than once every 15 seconds.
The OCR queue will retain only the newest changed screenshot.
Older queued screenshots will be discarded if recognition is still busy.
A screenshot will be retained only when it was analyzed or supports a detected meeting candidate.

## Local OCR and Meeting Detection

Zoid 0 will use Apple's Vision framework with accurate local text recognition.
English and Arabic recognition will be enabled when supported by the installed macOS version.
Zoid 0 will query the runtime-supported language list instead of assuming every language model is available.
Custom English and Arabic meeting vocabulary may supplement language correction.
Recognized text and screenshots will not be uploaded to a remote service.

Meeting detection will inspect changed screenshots from every application.
It will not be limited to WhatsApp.
The active application name and window title may be used as local context.
A candidate requires meeting intent plus a recognizable date and time.
Person, duration, and source context may improve the prepared confirmation form.
Low-confidence detections will be ignored.
Plausible detections will always require user review.

## Confirmation and Scheduling

A detected candidate will produce a desktop notification and an editable confirmation window.
The user may edit the title, person, date, start time, and duration.
Dismiss will create nothing.
Confirm will create one personal Apple Calendar event and one Apple Reminder.
The Reminder will be due at the meeting start.
The person's name will remain ordinary text.
No Calendar attendee will be added.
Processed visual fingerprints will suppress duplicate candidates and scheduling.

## Background Lifecycle

Closing the main window will hide the interface without terminating Zoid 0.
Capture and application-time tracking will continue in the same process.
Activating Zoid 0 from the Dock will restore the main window.
The application menu will retain an explicit Quit Zoid 0 command.
Quit will cancel capture, OCR, detection, and tracking tasks.
Quit will finalize the current application-time interval and close open metadata or database writes before process termination.

## User-Visible Health

The interface will show one of these honest states:

- Monitoring
- Analyzing changed screen
- Paused while idle
- Screen Recording permission needed
- Capture error

The application will not show Monitoring when capture is unavailable.
OCR failures will skip the affected screenshot without stopping later observations.
Malformed metadata will skip the affected record without stopping the service.

## Storage

One local store will hold application activity intervals, Safari website activity intervals, category assignments, daily totals, processed fingerprints, meeting candidates, and scheduling receipts.
Screenshot files will remain separate from structured records.
The storage boundary will support future retention controls without requiring them in this implementation.
No full activity history, deletion interface, or extensive evidence manager is included in this scope.

## Verification

Automated tests will prove:

- Launch starts capture when permission is available.
- Closing the window leaves capture and time tracking active.
- Quit stops capture and finalizes the active time interval.
- Application changes produce correct non-overlapping duration intervals.
- Safari active-tab changes produce correct non-overlapping domain intervals.
- Website records contain normalized domains and never full URLs, paths, queries, fragments, or page titles.
- Domain normalization handles public suffixes such as `co.uk` without merging unrelated websites.
- Safari website intervals replace matching Safari application time without double-counting.
- Missing extension permission falls back to generic Safari application time.
- The extension records nothing while the main Zoid 0 app is not running.
- Default category assignments apply only when no user assignment exists.
- User category assignments override defaults for applications and domains.
- Category totals equal the sum of their visible application and website contributors.
- Idle, sleep, lock, and inactive sessions are not attributed to an application.
- Unchanged screenshots do not run OCR.
- Changed screenshots use a latest-only bounded OCR queue.
- OCR runs no more than once every 15 seconds.
- Meeting detection works across application sources.
- English and Arabic fixtures produce editable candidates.
- Duplicate screenshots produce one candidate.
- Dismiss creates no Calendar event or Reminder.
- Confirmation creates one event and one Reminder with no attendees.

Signed application verification will cover:

- First-run Screen Recording permission.
- Permission persistence after relaunch.
- Background capture after closing the window.
- Capture termination after explicit Quit.
- Application-time totals from real application switches.
- Safari domain totals from real active-tab changes after explicit extension permission.
- Revoking Safari extension permission falls back to generic Safari time.
- A changed-screen meeting flow through notification and confirmation.
- A real Calendar event and Reminder created only after confirmation.
- A proof screenshot of the implemented interface and health state.

## Out of Scope

- A separate helper, daemon, or login item.
- Capture that continues after Quit Zoid 0.
- Remote OCR or cloud screenshot processing.
- Automatic Calendar scheduling.
- Client communication.
- Full URLs, page titles, page contents, search queries, and per-page reports.
- Website tracking in browsers other than Safari.
- Automatic semantic classification based on webpage contents.
- Per-window time reports.
- Cross-device Screen Time synchronization.
- Windows or mobile support.
