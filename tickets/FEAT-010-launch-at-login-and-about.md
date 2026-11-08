# FEAT-010: Launch at login and an About item

**Type:** Feature · **Wave:** 2 · **Files:** `SettingsView.swift`, `FrameletApp.swift`, new small helper

## Problem

A menu-bar utility that doesn't offer to start at login feels unfinished. There's also
no way to see the app's version or third-party notices from the UI.

## Expected

- Settings → new **General** section (or tab): **Open at login** toggle backed by
  `SMAppService.mainApp` (register/unregister). Reflect the actual `status`, including
  `.requiresApproval`, with a button to open Login Items settings.
- Menu: **About Framelet** opens the standard About panel
  (`NSApp.orderFrontStandardAboutPanel`) with version (`CFBundleShortVersionString` +
  build), and credits that mention gifski and link to the bundled
  `ThirdParty/NOTICE.md`.

## Acceptance criteria

- [ ] Toggle state matches `SMAppService.mainApp.status` after relaunch.
- [ ] About panel shows the correct version and gifski credit.
- [ ] No crash when run via `swift run` (no bundle). Hide or disable gracefully there.
- [ ] build, tests, build-app, `--self-test` pass.
