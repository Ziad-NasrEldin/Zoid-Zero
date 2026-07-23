# Zoid 0 Integrated Capture and Time Tracking Design

Status: approved

## Purpose

Zoid 0 will become one native macOS application that owns application-time tracking, screen observation, local meeting detection, confirmation, Calendar creation, and Reminder creation.
The existing external Screenwatch installation will no longer be required.
Screenwatch will become an internal capture service inside the Zoid 0 process.

## Product Boundary

Zoid 0 will use one application bundle, one process, one stable bundle identifier, and one permission identity.
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

## Application Time Tracking

Application time tracking will not depend on screenshots or OCR.
Zoid 0 will subscribe to macOS `NSWorkspace` application-activation events.
Each activity interval will record the application's bundle identifier, display name, start time, end time, and duration.
The tracker will pause time attribution while the Mac is idle, locked, asleep, or the user session is inactive.
The first version will report daily application-level totals.
Browser websites, document names, and individual window-title totals are not required for the first version.

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

One local store will hold application activity intervals, daily totals, processed fingerprints, meeting candidates, and scheduling receipts.
Screenshot files will remain separate from structured records.
The storage boundary will support future retention controls without requiring them in this implementation.
No full activity history, deletion interface, or extensive evidence manager is included in this scope.

## Verification

Automated tests will prove:

- Launch starts capture when permission is available.
- Closing the window leaves capture and time tracking active.
- Quit stops capture and finalizes the active time interval.
- Application changes produce correct non-overlapping duration intervals.
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
- A changed-screen meeting flow through notification and confirmation.
- A real Calendar event and Reminder created only after confirmation.
- A proof screenshot of the implemented interface and health state.

## Out of Scope

- A separate helper, daemon, or login item.
- Capture that continues after Quit Zoid 0.
- Remote OCR or cloud screenshot processing.
- Automatic Calendar scheduling.
- Client communication.
- Per-website or per-window time reports.
- Cross-device Screen Time synchronization.
- Windows or mobile support.
