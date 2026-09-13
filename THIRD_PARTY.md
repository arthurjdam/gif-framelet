# Third-Party Components

Framelet bundles **gifski 1.34.0**, built from the published Rust crate with its
default features (including PNG input and lossy GIF optimization). It does not
bundle or link FFmpeg. Rust is a build-time requirement, not an end-user dependency.

- Project and commercial licensing: https://gif.ski
- Source: https://github.com/ImageOptim/gifski/tree/1.34.0
- Crate: https://crates.io/crates/gifski/1.34.0
- License: AGPL-3.0-or-later, or a separately obtained commercial license.
- The upstream license is downloaded at build time and included in the app at
  `Contents/Resources/ThirdParty/gifski-LICENSE`.

gifski includes dependencies with their own notices and licenses, including
imagequant. The exact dependency versions are selected by the upstream lockfile
through `cargo install --locked`. Downloaded sources are in Cargo's registry cache.

## Distribution Gate

This is a development build, not a license-cleared release. Before distributing
the app, choose an AGPL-compliant distribution strategy or obtain appropriate
commercial licenses. Audit the locked transitive dependencies, include their
required notices, and provide corresponding source and build instructions wherever
their licenses require it. Bundling a command-line helper does not by itself remove
license obligations. No license for Framelet's own source is selected by this scaffold.

Apple frameworks (AppKit, SwiftUI, ScreenCaptureKit, AVFoundation, ImageIO) are
provided by macOS and are not redistributed with Framelet.