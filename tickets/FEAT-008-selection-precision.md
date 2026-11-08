# FEAT-008: Keyboard nudging and output pixel size in the selector

**Type:** Feature · **Wave:** 1 · **Files:** `Sources/Framelet/RegionSelector.swift` (+ pass settings in from `AppController` if needed)

## Problem

Getting a selection exactly right needs pixel-perfect mouse work. The toolbar shows
size in points (`400 × 250 pt`), but users care about the GIF's pixel size, which
depends on display scale and the max-width setting.

## Expected

- Arrow keys move the selection by 1 pt, Shift+Arrow by 10 pt. Option+Arrow
  grows/shrinks the right/top edge by 1 pt, and Shift+Option+Arrow by 10 pt. The
  selection stays clamped to the screen and at least 16×16.
- The toolbar shows the output size, e.g. `400 × 250 pt → 800 × 500 px`, using
  `CaptureRegion.pixelSize(scale:maximumWidth:)` with the panel screen's
  `backingScaleFactor` and the current max-width setting. Widen the toolbar if needed and keep it on-screen.
- Arrow keys must reach the view. `SelectionPanel.sendEvent` currently only forwards
  Return/Space/Escape.

## Acceptance criteria

- [ ] Nudge/resize via keyboard works and is clamped. No changes while recording.
- [ ] Pixel size shown and correct for scale 1 and 2, and for the max-width cap.
- [ ] `RegionSelector.checkInteractions` extended to cover nudge, resize, and label text.
- [ ] README "Record" section mentions the keys.
- [ ] build, FrameletChecks, build-app, `--self-test` pass.
