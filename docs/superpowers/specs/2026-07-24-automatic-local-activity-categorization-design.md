# Automatic Local Activity Categorization

## Goal

Zoid 0 categorizes observed applications and Safari website domains without asking for approval.
Classification remains entirely on the Mac.
A manual correction is a durable override until the user explicitly resets that item to automatic behavior.

## Inputs and privacy

Application classification may use only the stable bundle identifier and localized application name already captured by application tracking.
Website classification may use only the normalized registrable domain already produced by the Safari bridge.
The classifier must never receive or persist a full URL, URL path, query, page title, window title, screen text, screenshot, or activity history.
No cloud model or network service is used.

## Resolution order

Category resolution follows one fixed order:

1. A durable manual override.
2. A persisted automatic assignment.
3. The conservative built-in assignment table.
4. `uncategorized`.

Automatic processing may never replace a manual override.
Reset removes only the manual override, then immediately re-runs local automatic classification for that stable subject.

## Local classification

The deterministic classifier runs first.
It uses exact known bundle identifiers and domains, conservative bundle/domain tokens, and the localized application name.
Ambiguous or unknown metadata remains `uncategorized`.

On supported macOS 26 systems, Apple Foundation Models may be used only after deterministic classification declines.
The framework is on-device and already supported by this project and toolchain.
Its generated response is constrained to the existing category list plus a confidence value.
Only high-confidence supported results are accepted.
Unavailable Apple Intelligence, unsupported locale, refusal, generation failure, and low confidence all fall back to `uncategorized`.

## Persistence, migration, and history

The existing `categoryAssignments` field is decoded as manual overrides to preserve every prior user choice.
Automatic assignments are stored in a new optional field, so existing stores migrate without rewriting data.
At startup, the store derives unique subjects and safe metadata from existing app and website intervals and backfills only subjects without a manual override.
New observations are categorized through the same idempotent processor.
Automatic assignments may be refreshed by later classifier versions, but manual overrides are immutable until reset.

## Correction behavior

Choosing a category in the existing row menu writes a manual override.
The row identifies that its current value is manual.
The menu exposes `Reset to Automatic` for manually overridden items.
Reset removes the manual value and applies the best local automatic result.
Learning is deliberately limited to the exact stable subject.
Zoid 0 does not generalize one correction to other apps or domains because doing so could silently create incorrect or sensitive inferences.

## Failure behavior

Classification never blocks tracking, Safari ingestion, capture, meetings, or app shutdown.
Persistence or model failures leave the subject uncategorized.
No approval prompt, alert, or outbound request is introduced.
