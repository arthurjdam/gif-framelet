# Wave 1 QA (`integration` @ 614619a)

The reviewer/tester's verdict was **fix first**. Every automated check passed: a
warning-free build, 9 `swift test` tests, a code-signed bundle, and `--self-test`
3× stable at 12/12 (export of the 10 s fixture ≈0.8 s).

## Must fix before the PR
- **S1** — A failed replacement capture can delete the good recovery it was meant
  to replace (`keepForRetry` accepts an empty or unfinished `capture.mp4`). Being
  fixed together with N1 on `qa/FIX-002-S1`.
- **S2** — While capture is "Starting", there's no Cancel menu item and no way to
  quit, and a hung start leaves the app stuck in `.stopping`. Being fixed on
  `qa/FIX-001-S2`.
- **N1** — A cancelled selection or start while a recovery is pending shows
  "Ready to record" instead of "Recording saved for retry". Fixed together with S1.

**Status:** S2 is merged (a92a2aa), and S1 + N1 are merged (25e5d7a). N7, which the
senior engineer found, is merged (e0f6617): a stream error during startup now
cancels the start, so no capture is left running unattended. **Re-check at e0f6617:
SHIP.** Gate is green and `--self-test` passes 13/13 twice.

## Deferred nits (wave 2 or backlog)
- **Layering** — `ScreenRecorder.discard()` calls `AppController.removeTake`. Move
  the helper into the recorder or a small file utility the next time this code changes.
- **N8** — Theoretical stuck state: if the start task's discard branch ever runs
  for a cancelled start, the app stays in `.stopping` and `cancellingStart`
  never resets. Unreachable today. Fix: reset both in that branch.
- **N9** — "Cancel and Quit", or quitting while a failed start is still
  unwinding, can leave an empty `$TMPDIR/Framelet-*` folder. Fix: clean it up in
  `applicationWillTerminate`.
- **N2** — If the folder disappears mid-export, the message is readable but no
  "Choose Folder…" alert appears.
- **N3** — The `.inTrash` check uses the user-domain Trash, so it may not detect
  `/Volumes/X/.Trashes`. Unverified.
- **N4** — The AVAssetReader path tags frames as sRGB regardless of the track's
  color tags. Compare colors in manual QA step 1.
- **N5** — The self-test touches the real `~/.Trash`. Cleanup works, but the test
  fails where no Trash is available.
- **N6** — Skipped samples are still converted to `CGImage`. The cost is negligible.

## Manual QA checklist (needs real screen-recording permission)

1. **Normal record → export:** record about 5 s on a Retina display with the
   pointer moving.
   - The GIF animates (it doesn't freeze on the first frame).
   - Its pixel size matches the toolbar's "→ W × H px".
   - Colors match the screen (N4).
   - The temp folder is removed afterwards.
2. **Stop during "Starting":** press the shortcut twice quickly. Repeat while
   unplugging a display, and again while putting the Mac to sleep.
   - The app returns to Ready with no error.
   - The macOS recording indicator turns off.
   - No `$TMPDIR/Framelet-*` folder is left.
   - Also use the menu's **Cancel** item during "Starting capture". With a
     recovery pending, the status returns to "Recording saved for retry".
3. **Replace-recovery alert:** cancel an export to create a recovery, then press
   the shortcut.
   - **Cancel** does nothing.
   - **Reveal Previous** shows the old recording in Finder.
   - **Record and Replace** opens the selector. Escaping the selector keeps the
     old recovery.
   - After a successful export, the old folder is gone.
   - Choose Replace, record a static region and stop within about 0.5 s, so no
     frames are captured. Expect "no usable video… previous recording is still
     available"; Retry exports the old take.
   - Choose Replace, then unplug or rearrange the display during Starting. Expect
     an error, the old recovery still listed, and no new `$TMPDIR/Framelet-*`
     folder.
4. **Choose Folder alert:**
   - Delete the output folder in Finder. Settings shows the orange warning.
   - Record and stop. The alert appears before any export progress.
     **Choose Folder…** opens the picker over Settings, and **Retry** then
     succeeds.
   - Repeat with the folder in the Trash, and with an ejected external drive.
   - Move the folder and relaunch: Settings shows the new path.
5. **Arrow-key nudging on real panels:**
   - Arrow moves 1 pt and Shift+Arrow moves 10 pt.
   - Option+Arrow resizes the right/top edge, and Shift+Option+Arrow resizes in
     10 pt steps.
   - The selection stays inside screen edges and is never smaller than 16×16.
   - On a second display, arrows act on the panel you drew on.
   - The toolbar stays on-screen.
   - While recording, arrows go to the recorded app and the border doesn't move.
6. **Retry after relaunch:** record at 10 fps and cancel the export. Set fps to
   30, quit, relaunch and retry. The GIF is 10 fps and its duration is correct.
7. **Quit in each phase:**
   - Selecting: the selection cancels and the app quits.
   - Starting: "Capture is still starting…". **Cancel and Quit** quits
     immediately and the recording indicator goes off.
   - Stopping: "Wait for the recording to finish saving."
   - Recording: **Stop Recording** stops the recording but doesn't quit.
   - Exporting: an alert appears.
   - Failed with a recovery: the app quits, and the recovery is restored on the
     next launch.
8. **Settings → Encoder** shows 1.34.0.
