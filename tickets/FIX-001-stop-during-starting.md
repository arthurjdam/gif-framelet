# FIX-001: Stopping while capture is starting leaves the stream running

**Type:** Bug · **Wave:** 1 · **Files:** `Sources/Framelet/AppController.swift`, `Sources/Framelet/ScreenRecorder.swift`

## Problem

`AppController.stop()` (AppController.swift:144) accepts `.starting` as well as `.recording`.
If the user presses the shortcut (or the duration/sleep/display-change interrupt fires)
while `recorder.start(...)` is still awaiting `SCShareableContent` / `startCapture()`:

1. `stop()` sets `.stopping` and calls `recorder.stop()`. `stream` is still `nil`, so it
   throws "No recording is active." and the controller fails.
2. `start`'s task then resumes. `startCapture()` succeeds, `guard phase == .starting`
   (AppController.swift:122) returns early, and **the SCStream keeps capturing** with no
   owner. The macOS recording indicator stays on until quit.

## Expected

A stop requested during `.starting` cancels the start cleanly. The stream is never left
running, no error is shown, the temporary directory is removed, and the app returns
to `.idle`.

## Acceptance criteria

- [ ] Stop/interrupt during `.starting` results in `.idle` with no error and no running stream.
- [ ] If `startCapture()` completes after cancellation was requested, the stream is stopped
      and its temp directory deleted.
- [ ] Normal start→record→stop is unchanged.
- [ ] A self-check (in the style of `ScreenRecorder.checkSystemStop`) covers
      "stop requested before start completes" without needing real capture permission
      (e.g. by injecting the start step or testing the recorder's state flags directly).
- [ ] `swift build`, `swift run FrameletChecks`, `scripts/build-app.sh`, and `--self-test` pass.
