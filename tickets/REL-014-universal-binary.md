# REL-014: Universal (arm64 + x86_64) build

**Type:** Release · **Status:** Backlog. Needs an owner decision.

macOS 26 still runs on some Intel Macs, but the release scripts produce arm64 only.
Supporting Intel means `swift build --arch arm64 --arch x86_64`, `rustup target add
x86_64-apple-darwin`, building gifski for both targets, `lipo -create`, and updating
the artifact names in `package-*.sh` and RELEASING.md.

**Decision needed:** Is Intel support worth roughly doubling encoder build time and
testing on hardware we may not have?
