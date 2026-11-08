# FEAT-007: Record the last region again

**Type:** Feature · **Wave:** 2 · **Files:** `AppController.swift`, `AppSettings.swift`, `RegionSelector.swift`, `FrameletApp.swift`

## Problem

Re-recording the same area (a common "take two") means drawing the rectangle again.

## Expected

- After any recording starts, persist the region (global rect + display ID) in UserDefaults.
- Menu: **Record Last Region** (enabled when a stored region's display is still
  connected and the rect still fits). It skips drawing and goes straight to recording.
- When region selection opens, the last region on the current display is pre-selected
  (with toolbar shown), so Space/Return records it right away. Clicking outside it draws new.
- Skip the pre-selection when the display has changed geometry since.

## Acceptance criteria

- [ ] Region persisted and restored across launches. Ignored if the display is gone or resized.
- [ ] Menu item works, and pre-selection works in the selector.
- [ ] Self-check for persistence round-trip and validity rules.
- [ ] README updated.
- [ ] build, tests, build-app, `--self-test` pass.
