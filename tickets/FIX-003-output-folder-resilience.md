# FIX-003: Missing or moved output folder fails export late and opaquely

**Type:** Bug · **Wave:** 1 · **Files:** `AppSettings.swift`, `AppController.swift`, `SettingsView.swift`

## Problem

- `AppSettings.init` resolves the output bookmark but ignores `bookmarkDataIsStale`
  (AppSettings.swift:38), so a moved folder's bookmark is never refreshed.
- If the folder was deleted or an external volume was ejected, the failure only shows
  up *after* frame extraction and encoding, as a raw Cocoa error on `copyItem`.
- Settings shows the stale path with no hint that it no longer exists.

## Expected

- A stale bookmark is re-created after resolving.
- Before export starts (and when Settings opens), check that the folder exists and
  is writable. If not, fail fast with a clear message that names the folder and offers
  "Choose Folder…". Keep the movie for retry, which already happens.
- Settings shows a warning next to the destination when it is missing or not writable.
- Do **not** silently fall back to Desktop. The user chose that folder.

## Acceptance criteria

- [ ] Stale bookmarks are refreshed and persisted.
- [ ] Export to a missing folder fails before frame extraction, with a readable message.
- [ ] Settings indicates a missing or unwritable destination.
- [ ] Self-check: the validation helper reports missing/unwritable/ok correctly.
- [ ] build, FrameletChecks, build-app, `--self-test` pass.
