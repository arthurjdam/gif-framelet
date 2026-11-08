# FIX-002: A pending recovery blocks all new recordings

**Type:** Bug/UX · **Wave:** 1 · **Files:** `AppController.swift`, `FrameletApp.swift`, `SettingsView.swift`

## Problem

After any failed or cancelled export, `recoveryMovie` is set. Then:

- "Record Region…" is disabled (FrameletApp.swift:62).
- The global shortcut opens Settings instead of recording (AppController.swift:77).

The user has to retry or discard the old take before recording anything new. Cancelling
an export because the settings were wrong, then wanting to quickly re-record, is a
normal workflow, and right now it is blocked.

Also, the export fps for a retry comes from `recordingOptions` (AppController.swift:180),
which is in memory only. After a restart, a retry uses the *current* fps setting
instead of the fps the movie was captured at.

## Expected

- Recording is always allowed when idle/failed. Starting a new recording while a
  recovery exists keeps the old recovery available. Pick one approach and document it:
  either (a) support several recoveries, listed in the menu, or (b) keep one
  recovery and ask before replacing it ("Keep previous recording for retry?" →
  Discard / Reveal). (b) is acceptable and simpler.
- Recovery metadata (at least capture fps) is persisted next to the movie (e.g.
  a small JSON sidecar in the `Framelet-<uuid>` temp dir) and used on retry after a restart.

## Acceptance criteria

- [ ] With a pending recovery, the shortcut and menu item start region selection.
- [ ] The old recovery is not lost silently. The user is asked, or it stays listed.
- [ ] A retry after a relaunch uses the fps the movie was recorded at.
- [ ] README "Files"/recovery text updated.
- [ ] Self-check covers sidecar write/read round-trip.
- [ ] build, FrameletChecks, build-app, `--self-test` pass.
