# Framelet tickets

Review date: 2026-11-08 (against `d2e21f5`).

The core loop (select → record → export GIF) works and is careful about failure
and recovery. What's missing for it to feel finished: a few state-machine bugs,
no way to discard or trim a take before encoding, no feedback after export
besides Finder, and test and CI coverage that doesn't scale.

## Workflow

- Each ticket is built by one **engineer** on its own branch, `ticket/<ID>`.
- The **senior engineer** reviews each branch against its ticket, asks for
  changes, and merges approved branches into `integration`.
- The **reviewer/tester** builds `integration`, runs `swift test` (was
  `swift run FrameletChecks` before TEST-013) and `Framelet --self-test`, and
  code-reviews the merged result.
- Each wave lands as a PR from `integration` → `main`, merged only after the owner signs off.

## Board

| ID | Type | Title | Wave | Status |
|----|------|-------|------|--------|
| [FIX-001](FIX-001-stop-during-starting.md) | Bug | Stopping while capture is starting leaves the stream running | 1 | Done (integration e0f6617), QA passed |
| [FIX-002](FIX-002-recovery-blocks-recording.md) | Bug | A pending recovery blocks all new recordings | 1 | Done (integration e0f6617), QA passed |
| [FIX-003](FIX-003-output-folder-resilience.md) | Bug | Missing/moved output folder fails export late and opaquely | 1 | Done (integration e0f6617), QA passed |
| [FEAT-008](FEAT-008-selection-precision.md) | Feature | Keyboard nudging and output pixel size in the selector | 1 | Done (integration e0f6617), QA passed |
| [PERF-012](PERF-012-faster-frame-extraction.md) | Perf | Sequential frame decode instead of per-frame seeking; typed export stages | 1 | Done (integration e0f6617), QA passed |
| [TEST-013](TEST-013-swift-testing-and-ci.md) | Infra | Move core checks to `swift test`, add CI | 1 | Done (integration e0f6617), QA passed |
| [FEAT-005](FEAT-005-discard-recording.md) | Feature | Discard an in-progress recording without exporting | 2 | Todo |
| [FEAT-006](FEAT-006-preview-and-trim.md) | Feature | Preview and trim before export | 2 | Todo |
| [FEAT-007](FEAT-007-record-last-region.md) | Feature | Record the last region again | 2 | Todo |
| [FEAT-009](FEAT-009-export-feedback.md) | Feature | Export notification, file size, auto-copy option | 2 | Todo |
| [FEAT-010](FEAT-010-launch-at-login-and-about.md) | Feature | Launch at login and an About item | 2 | Todo |
| [FEAT-011](FEAT-011-countdown.md) | Feature | Optional countdown before recording | 2 | Todo |
| [REL-014](REL-014-universal-binary.md) | Release | Universal (arm64 + x86_64) build | Backlog | Needs owner |
| [DEC-015](DEC-015-licensing.md) | Decision | Project license and gifski AGPL position | Backlog | Needs owner |
| [DOC-016](DOC-016-readme-polish.md) | Docs | README demo GIF, install section, honest tagline | Backlog | Todo |

Wave 1 covers fixes and isolated changes. Wave 2 covers features that all touch
`AppController` and start from the integrated wave 1.
