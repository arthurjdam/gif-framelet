# FEAT-006: Preview and trim before export

**Type:** Feature · **Wave:** 2 · **Files:** new `PreviewWindow.swift`, `GIFExporter.swift`, `AppController.swift`, `AppSettings.swift`, `SettingsView.swift`

## Problem

Every recording starts and ends with the user reaching for the shortcut, so the first
and last second of most GIFs is junk. There's no way to see the take before
spending time encoding it.

## Expected

- New setting **"Preview before export"** (GIF tab), default **on**.
- When on, stopping a recording opens a preview window instead of exporting right away:
  - `AVPlayerView` (AVKit) with the movie, looping, and its built-in trimming UI
    (`beginTrimming`) or an equivalent start/end range control.
  - Shows trimmed duration and output pixel size.
  - Buttons: **Export GIF** (default, Return), **Discard** (asks to confirm), and
    closing the window = keep as recovery (same as a cancelled export).
- `GIFExporter.export` takes an optional `CMTimeRange` and only samples frames inside it.
  `ExportOptions.frameCount` and timestamps are relative to the range start.
- When the setting is off, behaviour is unchanged.

## Acceptance criteria

- [ ] Trimmed export contains only the selected range (self-test: export a 0.5–1.5 s
      range of the 2 s fixture → ~1 s GIF, ~10 frames at 10 fps).
- [ ] Preview window is a normal key window (the app is `.accessory`, so activate it), works with the keyboard, and has VoiceOver labels.
- [ ] Recovery/retry still works if the preview is closed.
- [ ] README updated.
- [ ] build, tests, build-app, `--self-test` pass.
