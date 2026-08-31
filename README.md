# Zoid 0

A local-first macOS capture and time app — where your day went, and a meeting on Calendar only after you confirm it.

Built for a creator or operator on their own Mac who wants that picture without a cloud watching the screen, storing full URLs, or messaging anyone on their behalf.

- See daily time by app, then by Safari domain once the bundled extension is on
- Work, Communication, Social, Gaming, Media, Utilities, Browser — categorized on the Mac, with a manual override on any row
- App time does not need screenshots. Changed screens are read locally (English, Arabic, or mixed) only to catch possible meeting agreements
- Review uncertain fields, then confirm or dismiss. Confirm adds one personal Calendar event and one Reminder. No attendees, invitations, or messages
- Close the window and Zoid 0 keeps running from the menu bar; Quit is what stops capture. Launch at login, or hide the Dock icon, if you want it out of the way

## Try it

This is a native Mac app, not a website. You need macOS 26, Swift 6.2, Xcode (for the Safari extension), and an Apple Development signing identity.

```sh
swift test
./Scripts/build-app.sh
open ".build/Zoid 0.app"
```

If codesign cannot find an identity, set `ZOID_ZERO_SIGNING_IDENTITY`. Allow Screen Recording if you want meeting detection from the screen. Calendar and Reminders are requested only when you confirm. Website split stays off until you enable the Zoid 0 Safari extension and grant access — only the domain is stored.

Product specs live in [`docs/`](docs/). Nested `Atoll/` docs are an upstream vendor snapshot, not this app.

---

[MaVoid](https://mavoid.com) · [LinkedIn](https://linkedin.com/in/ziad-ahmed-634202332) · [GitHub](https://github.com/Ziad-NasrEldin)
