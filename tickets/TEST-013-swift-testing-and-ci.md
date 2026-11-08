# TEST-013: Move core checks to `swift test` and add CI

**Type:** Infra · **Wave:** 1 · **Files:** `Package.swift`, `Tests/`, `.github/workflows/`, `.vscode/tasks.json`, README

## Problem

`FrameletChecks` is an executable with `precondition`s. The first failure crashes, none
of the checks are named, there's no `swift test`, and nothing runs on push.

## Expected

- Convert `Tests/RecorderCoreTests/Checks.swift` to a real test target
  (`.testTarget(name: "RecorderCoreTests", dependencies: ["RecorderCore"])`) using
  **Swift Testing** (`import Testing`, `@Test`, `#expect`). Fall back to XCTest only if
  Swift Testing doesn't run with the Command Line Tools toolchain here, and say why.
- Split into named tests: coordinate conversion, secondary displays, clipping, min size,
  Retina scaling, export option bounds, argument building, frame count edge cases.
- Remove the `FrameletChecks` executable, or keep a thin alias, and update README,
  RELEASING.md, and `.vscode/tasks.json` to `swift test`.
- Add `.github/workflows/ci.yml` that runs `swift build` + `swift test` on the newest
  available macOS runner. Do **not** build gifski in CI for now (slow). The app self-test
  stays a local/preflight step. Note any runner/SDK caveats in the workflow comments.

## Acceptance criteria

- [ ] `swift test` passes locally and runs every former check as a named test.
- [ ] Docs and VS Code tasks reference `swift test`.
- [ ] CI workflow exists and is syntactically valid (it cannot be run from here; say so).
- [ ] `swift build`, build-app, `--self-test` still pass.
