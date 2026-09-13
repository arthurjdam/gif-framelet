# Releasing Framelet

## Important Constraints

- The current release scripts build an **arm64-only** app. Use it on Apple Silicon
  Macs running macOS 26 or later.
- A ZIP keeps the application bundle's executable bits and code signature intact;
  do not send the `.app` directory directly through chat or email.
- `scripts/package-internal.sh` creates an immediately shareable development ZIP,
  but it is ad-hoc signed and rejected by Gatekeeper on other Macs.
- `scripts/package-release.sh` creates the artifact suitable for coworkers and
  external distribution: Developer ID signed, notarized, stapled, ZIP packaged,
  and accompanied by SHA-256 checksum.
- Before any distribution, resolve the gifski AGPL/commercial license and
  transitive-notice requirements in [THIRD_PARTY.md](THIRD_PARTY.md).

## One-Time Apple Setup

1. Join the Apple Developer Program and create/download a **Developer ID
   Application** certificate for the team. Import it into the login keychain.
2. Verify it is visible:

   ```sh
   security find-identity -v -p codesigning
   ```

3. Create an app-specific password at appleid.apple.com, then enter the password
   directly in the terminal. Do not store the password in this repository.

   ```sh
   xcrun notarytool store-credentials FrameletNotary \
     --apple-id "you@example.com" \
     --team-id "TEAMID" \
     --password
   ```

4. Put the final app identifier, version, and Apple Developer team process in a
   release checklist. The identifier is currently `app.framelet.recorder`.

## Internal Preview

```sh
zsh scripts/package-internal.sh 0.1.0
```

This writes:

```text
dist/internal/Framelet-0.1.0-arm64-UNNOTARIZED.zip
dist/internal/Framelet-0.1.0-arm64-UNNOTARIZED.zip.sha256
```

Recipients should unzip it, move `Framelet.app` to `/Applications`, then
Control-click it in Finder and choose **Open**. They must do this once because
the archive is not notarized. Verify its supplied SHA-256 before opening it.

## Notarized Release

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="FrameletNotary" \
  zsh scripts/package-release.sh 0.1.0
```

The script refuses to produce a release without a matching Developer ID identity.
It builds with hardened runtime, signs the nested encoder before the app, submits
the ZIP to Apple, waits for acceptance, staples the ticket, validates with
Gatekeeper, and creates:

```text
dist/release/Framelet-0.1.0-arm64.zip
dist/release/Framelet-0.1.0-arm64.zip.sha256
```

Upload both files to the GitHub Release. Coworkers should verify the checksum,
unzip, and drag the app into `/Applications`. A notarized download should open
normally without the Control-click bypass.

## Preflight

Run before publishing:

```sh
swift run FrameletChecks
zsh scripts/build-app.sh
dist/Framelet.app/Contents/MacOS/Framelet --self-test
codesign --verify --deep --strict --verbose=4 dist/Framelet.app
spctl --assess --type execute --verbose=4 dist/Framelet.app
```

Perform a live recording test from a clean macOS 26 Apple Silicon account.