# FEAT-009: Export notification, file size, auto-copy option

**Type:** Feature · **Wave:** 2 · **Files:** `AppController.swift`, `AppSettings.swift`, `SettingsView.swift`, `FrameletApp.swift`

## Problem

When "Reveal in Finder" is off, a finished export is silent. The user never learns
the file size, and copying the GIF to paste into chat takes several menu clicks.

## Expected

- On success, post a `UNUserNotificationCenter` notification: "GIF saved —
  1.8 MB, 320×180, 4.2 s", with actions **Copy** and **Show in Finder**. Clicking the
  notification reveals the file. Request authorization lazily, on first export. If
  it's denied, everything else keeps working.
- New setting (Files tab): **Copy GIF to clipboard after export** (default off).
- The menu's "Show Last GIF" row shows the file size.
- Failures (not cancellations) also post a notification pointing to the menu.

## Acceptance criteria

- [ ] Notification shows size, dimensions, and duration. Actions work.
- [ ] Auto-copy puts the file URL on the pasteboard (same as the existing Copy GIF).
- [ ] Works when notification permission is denied.
- [ ] Size/dimension/duration formatting helper is unit- or self-tested.
- [ ] build, tests, build-app, `--self-test` pass.
