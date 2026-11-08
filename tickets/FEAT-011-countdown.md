# FEAT-011: Optional countdown before recording

**Type:** Feature · **Wave:** 2 · **Files:** `RegionSelector.swift`, `AppController.swift`, `AppSettings.swift`, `SettingsView.swift`

## Problem

Recording starts right when Record is pressed, so the first frames show the
user's hand moving back to the app being demoed.

## Expected

- Setting (Recording tab): **Countdown** — Off / 3 s / 5 s (default Off, so current behaviour is kept).
- When on: after Record, the selection border stays and a large translucent
  number counts down in the selection centre. The overlay is click-through during the
  countdown, and the previous app is reactivated right away so the user can set up.
  Capture starts when the countdown hits 0, and the number is **not** in the capture
  (Framelet's windows are already excluded, so verify that).
- The shortcut or Escape-equivalent during the countdown cancels back to idle.
- Menu bar shows the countdown.

## Acceptance criteria

- [ ] Countdown visible, cancellable, and not captured.
- [ ] Off = identical to current flow.
- [ ] Self-check snapshot of the countdown overlay in `RegionSelector.checkInteractions`.
- [ ] README updated.
- [ ] build, tests, build-app, `--self-test` pass.
