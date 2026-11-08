# FEAT-005: Discard an in-progress recording without exporting

**Type:** Feature · **Wave:** 2 · **Files:** `AppController.swift`, `FrameletApp.swift`

## Problem

Once recording starts, every way to stop it (shortcut, menu, system stop button,
time limit) exports a GIF. A botched take has to be encoded and then deleted by hand.

## Expected

- Menu while recording: **Stop Recording** (as now) and **Discard Recording** (new).
- Keyboard: the configured shortcut + Option (e.g. ⌥⇧⌘8) discards. Register it as a
  second hot key only while recording, and unregister it otherwise. If registration
  fails, the menu item still works.
- Discard stops capture, deletes the temp directory, does **not** create a recovery,
  and returns to `.idle`. No confirmation needed, because the user asked for it explicitly.
- README updated.

## Acceptance criteria

- [ ] Discard from menu and from the Option-variant shortcut both work.
- [ ] No GIF is produced, the temp dir is removed, and `recoveryMovie` is unchanged
      (an older recovery, if any, is still there).
- [ ] Discard during `.starting` behaves like FIX-001's cancel.
- [ ] build, tests, build-app, `--self-test` pass.
