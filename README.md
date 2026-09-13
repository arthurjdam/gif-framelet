# Framelet

99% vibe-coded application to record gifs.

Written in Swift 6 with SwiftUI, AppKit, ScreenCaptureKit,
AVFoundation, and a bundled gifski encoder. No Electron, web view, runtime package
manager, microphone access, or Accessibility permission is required.

## Build and Run

Requirements: macOS 26+, the macOS 26 SDK and Swift 6 toolchain from Xcode or Command
Line Tools, and a current Rust stable toolchain installed through rustup. The first
build downloads gifski 1.34.0 and its locked dependencies.

```sh
rustup toolchain install stable --profile minimal
zsh scripts/build-app.sh
open dist/Framelet.app
```

The script builds for the current Mac's architecture, embeds the encoder, generates
the icon, checks the encoder for non-system dynamic dependencies, and ad-hoc signs
the app with hardened runtime enabled. End users do not need Rust or FFmpeg.
Full Xcode is not required to build this project. Use `swift build` for a quick
compile check; launch the bundled app, not `swift run Framelet`.

VS Code tasks are provided for building, checking, and launching. The Swift package
can also be opened in Xcode. Quit the running app before rebuilding its bundle.

## Record

1. Press **Command-Shift-8**, or choose **Record Region** in the menu bar.
2. Drag a rectangle on any connected display. Drag inside it to move it, or use its
   eight handles to resize. Dimensions are displayed in screen points.
3. Press **Space** or **Return**, or click **Record**. **Escape** cancels selection.
4. The border becomes solid red, controls disappear, and the surrounding screen dims subtly.
   The overlay becomes click-through so you can interact with the recorded app.
5. Press the same global shortcut again, choose **Stop Recording** in Framelet's menu,
  or use macOS's native recording stop button. All three finalize the movie and
  export a GIF. The Framelet menu-bar icon shows elapsed recording time.
6. The optimized GIF is saved to **~/Desktop** by default and revealed in Finder.

The region belongs to one display; it cannot span displays. Capture excludes
Framelet's own windows, including the selection overlay. A changed display layout
or sleep ends an active recording. No audio is recorded. Protected content may be
blank because of macOS or the source application's capture restrictions.

## Settings

- **Recording:** screen permission, pointer capture, outside dimming, automatic stop
  after 15/30/60/120 seconds, and a recordable global shortcut. Shortcut conflicts
  are reported; at least Command, Control, or Option is required.
- **GIF:** 5-30 fps, maximum width of 320-2560 pixels, quality of 20-100, faster
  encoding, and infinite looping or single playback. Retina scaling is respected;
  the capture stage does not upscale small selections.
- **Files:** destination folder, reveal-in-Finder preference, export progress,
  cancellation, and retry of a failed export.

Defaults: 15 fps, 1280-pixel maximum width, quality 80, infinite loop, pointer on,
outside dimming on, and a 60-second recording limit. Lower frame rates, widths, and
quality generally produce smaller files. Fast encoding trades compression and
quality for speed; it is not a smaller-file preset.

Recording is written to a temporary H.264 movie rather than accumulated in memory.
Export samples that movie at a fixed cadence, writes PNG frames, and invokes gifski
off the main thread. GIF timestamps retain static pauses. A destination-local
staging file prevents partially written final GIFs, and unique names prevent
overwriting previous exports.

Temporary frames are removed after export or cancellation. A failed/cancelled
export retains the original movie for retry, including after a normal app restart.
The recovery menu can reveal or explicitly discard it. The original is deleted
after successful export. Recovery lives in macOS temporary storage, so it is not a
long-term backup. Interrupted capture may produce an incomplete movie. Large or
long captures can need substantial temporary disk space.

## Verification

```sh
swift run FrameletChecks
zsh scripts/build-app.sh
dist/Framelet.app/Contents/MacOS/Framelet --self-test
```

To retain selection/recording PNG snapshots:

```sh
FRAMELET_TEST_ARTIFACTS="$PWD/.build/validation" \
  dist/Framelet.app/Contents/MacOS/Framelet --self-test
```

## Distribution

This is a working development build, not an App Store or notarized release. The
current artifact is Apple Silicon-only. For an internal preview ZIP, run:

```sh
zsh scripts/package-internal.sh
```

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="FrameletNotary" zsh scripts/package-release.sh
```

## Code Layout

- [Sources/Framelet](Sources/Framelet): app lifecycle, menu bar, settings, shortcut,
  selection panels, ScreenCaptureKit recorder, exporter, and native self-checks.
- [Sources/RecorderCore](Sources/RecorderCore): capture geometry and export options.
- [Tests/RecorderCoreTests](Tests/RecorderCoreTests): standalone core checks.
- [scripts/build-app.sh](scripts/build-app.sh): reproducible app bundle build.