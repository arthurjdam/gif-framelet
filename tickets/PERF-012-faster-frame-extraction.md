# PERF-012: Sequential frame decode and typed export stages

**Type:** Performance/Refactor · **Wave:** 1 · **Files:** `GIFExporter.swift`, `AppController.swift`, `SettingsView.swift`

## Problem

1. `GIFExporter.export` calls `AVAssetImageGenerator.image(at:)` once per output frame
   (GIFExporter.swift:32). Each call seeks and decodes from the nearest keyframe, so
   a 60 s / 30 fps capture (1,800 frames) runs extraction in O(frames × GOP).
2. Export progress stages are bare strings compared by value
   (`exportStage == "Preparing frames"` in AppController.swift:36 and SettingsView.swift:85).
3. The gifski version `"1.34.0"` is hard-coded in SettingsView.swift:65 and again in
   build-app.sh.

## Expected

1. Decode the movie in a single forward pass (`AVAssetReader` +
   `AVAssetReaderTrackOutput`, 32BGRA). For each output timestamp
   `i / fps`, pick the latest decoded frame whose PTS ≤ timestamp (hold the last frame
   for static stretches, as now). Keep PNG writing in `autoreleasepool`. Keep
   cancellation checks. Keep the existing output (same frame count, same dimensions,
   duration within tolerance).
2. Replace the stage string with an `enum ExportStage { case preparingFrames, optimizing }`
   with a display string. Update every comparison.
3. Read the encoder version from one place: run `gifski --version` once, lazily, or
   put the version into Info.plist at build time. Settings displays that value.

## Acceptance criteria

- [ ] Existing `--self-test` GIF checks (frame count 18–21, 320×180, duration ≈2 s, loop flags) pass unchanged.
- [ ] Add a timing print in self-test for a longer fixture (e.g. 10 s @ 30 fps) and record before/after numbers in the PR/commit message.
- [ ] No string comparisons of export stage remain.
- [ ] Version string has a single source of truth.
- [ ] build, FrameletChecks, build-app, `--self-test` pass.
