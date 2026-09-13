#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

version="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
identity="${SIGN_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-FrameletNotary}"
archive_root="$PWD/dist/release"
archive="$archive_root/Framelet-$version-arm64.zip"

if [[ -z "$identity" || "$identity" == "-" ]]; then
    print -u2 "A Developer ID signing identity is required for a shareable release."
    print -u2 "Example: SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' $0 $version"
    print -u2 "Available identities:"
    security find-identity -v -p codesigning
    exit 1
fi

if ! security find-identity -v -p codesigning | /usr/bin/grep -Fq "$identity"; then
    print -u2 "Signing identity not found: $identity"
    exit 1
fi

SIGN_IDENTITY="$identity" zsh scripts/build-app.sh
rm -rf "$archive_root"
mkdir -p "$archive_root"
ditto -c -k --sequesterRsrc --keepParent dist/Framelet.app "$archive"

xcrun notarytool submit "$archive" --keychain-profile "$notary_profile" --wait
xcrun stapler staple dist/Framelet.app
xcrun stapler validate dist/Framelet.app
codesign --verify --deep --strict --verbose=4 dist/Framelet.app
spctl --assess --type execute --verbose=4 dist/Framelet.app

rm "$archive"
ditto -c -k --sequesterRsrc --keepParent dist/Framelet.app "$archive"
shasum -a 256 "$archive" > "$archive.sha256"
print "Notarized release: $archive"
print "SHA-256: $archive.sha256"