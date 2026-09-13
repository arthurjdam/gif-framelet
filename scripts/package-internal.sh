#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

version="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
archive_root="$PWD/dist/internal"
archive="$archive_root/Framelet-$version-arm64-UNNOTARIZED.zip"

zsh scripts/build-app.sh
rm -rf "$archive_root"
mkdir -p "$archive_root"
ditto -c -k --sequesterRsrc --keepParent dist/Framelet.app "$archive"
shasum -a 256 "$archive" > "$archive.sha256"
print "Internal-only archive: $archive"
print "SHA-256: $archive.sha256"
print "This archive is ad-hoc signed and will be rejected by Gatekeeper on other Macs."