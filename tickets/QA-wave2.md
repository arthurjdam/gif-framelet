# Wave 2 QA (`integration` @ 2f9ac20)

**Verdict: SHIP.** All automated checks pass:
- a clean build with no warnings
- `swift test` 13/13
- the app bundle verifies with codesign
- `--self-test` passes 18/18 on 3 runs in a row. The timed export, trimmed export and countdown snapshot were stable across those runs.

Merged in this order: FEAT-010 → FEAT-007 → FEAT-011 → FEAT-005 (+N8) → FEAT-006 → FEAT-009 (+N2).

## Known issues (follow-ups)
- **W1 (should-fix)**: the trim is lost on a retry. Trim in the preview, then
  Export fails (missing folder, cancel, encoder error). Retry exports the whole
  take. This is documented in the README, but the Choose Folder flow leads
  people straight into it. Fix: store the range in `recovery.json` next to
  `fps`, or reopen the preview on Retry.
- **N10**: quitting while the preview is open gives no prompt, and the trim is
  lost. The take is still kept.
- **N11**: Discard in the preview can't bring back an older recovery. That
  recovery was already replaced when the new take finished, as agreed in
  FIX-002's prompt.
- **N12**: the GIF settings are disabled while the preview is open, so quality,
  width and loop can't be changed just before Export.
- **N13**: after the replace-recovery alert, the selector records Framelet as
  the app to return focus to. Focus then doesn't go back to the user's app when
  the countdown or recording starts. Fix: remember the frontmost app before the
  alert.
- **N9 / N14**: "Cancel and Quit" can leave an empty `$TMPDIR/Framelet-*`
  folder. Still open from wave 1.
- Backlog from the senior engineer:
  - Persist the trim for retry (same as W1).
  - Bundle NOTICE as `.txt` (with DEC-015).
  - Move `removeTake` out of `AppController`.

## Manual QA checklist (needs real screen-recording permission)
Wave 1 steps 1–8 in `QA-wave1.md` still apply. One change: **preview is now on
by default**, so the GIF is exported from the preview with Return.

1. **Preview, default flow**: record about 5 s and stop.
   - The preview opens as the key window and loops.
   - Set Start to about 1 s and End to about 4 s. The summary shows about
     3 s, the frame count, and W×H px.
   - Space pauses and resumes playback.
   - Return exports. The GIF is about 3 s long, and the notification reads
     "GIF saved — size, W×H, 3.0 s".
   - VoiceOver reads the sliders and the summary.
2. **Preview, keep and close**:
   - Escape, **Keep for Later** and the close button each give "Recording
     saved for retry".
   - Retry exports the full take.
   - Quit while the preview is open, then relaunch: the recovery is restored.
3. **Preview, discard**:
   - The confirmation sheet appears.
   - After discarding, no `$TMPDIR/Framelet-*` folder is left.
   - With an older recovery: choose Replace, then Discard in the preview. No
     recovery remains (N11).
4. **Preview with a missing folder**: delete the output folder, then press
   Export in the preview.
   - The Choose Folder alert appears.
   - After choosing a folder, Retry exports the take untrimmed (W1).
5. **Preview off**: stopping exports immediately, as in wave 1.
6. **Countdown, 3 s and 5 s**:
   - The border stays on screen and a number counts down in the selection.
   - The previous app is active and clicks pass through to it.
   - The menu bar shows the seconds left.
   - Neither the number nor the border appears in the GIF.
   - The shortcut, the menu's **Cancel Countdown**, unplugging a display and
     sleeping the Mac each cancel the countdown. Each returns to Ready, or to
     Failed if a recovery is pending.
   - Quitting during the countdown quits immediately.
7. **Record Last Region**:
   - Records the same rect without drawing, including the countdown when it's
     on.
   - Opening the selector pre-selects the rect with the toolbar; Space records
     it, and clicking outside draws a new selection.
   - Changing the resolution or arrangement, or unplugging the display,
     disables the menu item and removes the pre-selection.
   - The region survives a relaunch.
   - On a second display, it records on the correct display.
8. **Discard while recording**:
   - The menu's **Discard Recording** and ⌥⇧⌘8 both stop without exporting
     and leave no temp folder. An older recovery is still listed afterwards.
   - ⌥⇧⌘8 does nothing when not recording.
   - With a shortcut that already includes Option, Settings shows the caption
     and the menu item still works.
9. **Notifications**:
   - The permission prompt appears on the first export.
   - **Copy** pastes the GIF, and **Show in Finder** or clicking the
     notification reveals it.
   - A cancelled export posts nothing.
   - An export failure posts "GIF export failed"; clicking it shows the error.
   - With permission denied, export still works and nothing is posted.
   - After quitting, clicking the notification relaunches the app and reveals
     the GIF.
10. **Copy after export**: turn it on, export, then paste. The menu's "Show Last
    GIF in Finder (… MB)" shows the size.
11. **Open at login and About**:
    - Turn the toggle on, then log out and back in: Framelet launches.
    - In the "requires approval" state, the warning and the **Open Login Items
      Settings** button appear.
    - The toggle state is correct after a relaunch.
    - The About panel shows "0.1.0 (1)", "gifski 1.34.0" and a working
      "Third-party notices" link.
    - On an ad-hoc-signed build, if registration fails, the error is shown.
