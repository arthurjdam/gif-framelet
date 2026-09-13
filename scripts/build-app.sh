#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

encoder_version="1.34.0"
encoder_root="$PWD/.build/encoder"
app="$PWD/dist/Framelet.app"
identity="${SIGN_IDENTITY:--}"

if [[ ! -x "$encoder_root/bin/gifski" ]]; then
    if ! command -v cargo >/dev/null; then
        print -u2 "Rust is required to build the bundled encoder. Install Rust from https://rustup.rs and run this script again."
        exit 1
    fi
    cargo +"${RUST_TOOLCHAIN:-stable}" install gifski --version "$encoder_version" --locked --root "$encoder_root"
fi
if [[ "$("$encoder_root/bin/gifski" --version)" != "gifski $encoder_version" ]]; then
    print -u2 "Unexpected encoder version in $encoder_root. Expected gifski $encoder_version."
    exit 1
fi

swift build -c release --product Framelet
bin_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources/ThirdParty"
cp "$bin_dir/Framelet" "$app/Contents/MacOS/Framelet"
cp "$encoder_root/bin/gifski" "$app/Contents/Helpers/gifski"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp THIRD_PARTY.md "$app/Contents/Resources/ThirdParty/NOTICE.md"

mkdir -p .build/licenses
if [[ ! -f .build/licenses/gifski-LICENSE ]]; then
    curl --fail --location --retry 2 "https://raw.githubusercontent.com/ImageOptim/gifski/$encoder_version/LICENSE" --output .build/licenses/gifski-LICENSE
fi
cp .build/licenses/gifski-LICENSE "$app/Contents/Resources/ThirdParty/"
swift scripts/make-icon.swift .build/Framelet.iconset
iconutil -c icns .build/Framelet.iconset -o "$app/Contents/Resources/Framelet.icns"

if otool -L "$app/Contents/Helpers/gifski" | tail -n +2 | awk '{print $1}' | /usr/bin/grep -Ev '^(/usr/lib/|/System/Library/)' >/dev/null; then
    print -u2 "The encoder has non-system dynamic dependencies; refusing to package it."
    exit 1
fi

codesign --force --options runtime --sign "$identity" "$app/Contents/Helpers/gifski"
codesign --force --options runtime --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
print "Built $app"
print "Run: open \"$app\""