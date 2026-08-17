# Zoid 0

Private local-first macOS app for screen capture, time tracking, and meeting confirmation — nothing leaves the Mac unless you confirm a calendar or reminder change.

## Who it's for

You, on your own Mac, when you want application and Safari time, meeting candidates from the screen, and a confirmation step before Calendar or Reminders change. Not a cloud tracker and not a public product.

## What you can do

- Watch changed screens locally (ScreenCaptureKit + on-device OCR) and queue meeting candidates for review.
- Track application time and, when the bundled Safari extension is enabled, website time.
- Confirm or dismiss each meeting. Zoid 0 never messages another person and never writes Calendar or Reminders until you confirm.
- Keep activity, categories, candidates, and receipts in a local store under Application Support (ZoidZero/store.json).
- Run in the menu bar with launch-at-login and optional Dock visibility. Closing the window does not quit capture.

## Try it

Default branch is `codex/zoid-zero-final-release`. Do not change it.

Requires macOS 26+, Swift 6.2 tools, and an Apple Development signing identity.

```sh
swift build --product ZoidZero
./Scripts/build-app.sh
open ".build/Zoid 0.app"
```

Scripts/build-app.sh builds the app, embeds Zoid 0 Extension.appex, and codesigns both. Set ZOID_ZERO_SIGNING_IDENTITY if needed.

```sh
swift test
```

On first capture, grant Screen Recording. Calendar and Reminders are requested only when you confirm a meeting. Safari website tracking stays off until you enable the bundled extension.

## How it works

Swift package targets: ZoidZeroApp (SwiftUI + menu bar), ZoidZeroCore (models and workflows), ZoidZeroInfrastructure (capture, Safari inbox, local store, Apple Calendar/Reminders).

Meeting detection uses on-device Foundation Models when available, with a local English/Arabic parser fallback. Screenshots, OCR, and model output stay on the Mac. Atoll is vendored for Dynamic Island-style meeting prompts. Engineer specs and plans live in docs/.

---

Built by [Ziad Ahmed](https://github.com/Ziad-NasrEldin) at [MaVoid](https://mavoid.com).

[Website](https://mavoid.com) · [LinkedIn](https://linkedin.com/in/ziad-ahmed-634202332) · [GitHub](https://github.com/Ziad-NasrEldin)
