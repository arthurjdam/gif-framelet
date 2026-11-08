import Foundation
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
import RecorderCore

private let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let small = CGRect(x: 0, y: 0, width: 100, height: 100)
private let options = ExportOptions(fps: 100, maximumWidth: 9999, quality: 0, fast: true, loops: false)

private func region(_ rect: CGRect, in bounds: CGRect) throws -> CaptureRegion {
    try #require(CaptureRegion(rect: rect, displayBounds: bounds))
}

@Test func coordinateConversion() throws {
    let primary = try region(CGRect(x: 100, y: 200, width: 300, height: 180), in: laptop)
    #expect(primary.sourceRect == CGRect(x: 100, y: 520, width: 300, height: 180))
}

@Test func secondaryDisplays() throws {
    let secondary = try region(
        CGRect(x: -1800, y: 1000, width: 600, height: 400),
        in: CGRect(x: -1920, y: 900, width: 1920, height: 1080)
    )
    #expect(secondary.sourceRect == CGRect(x: 120, y: 580, width: 600, height: 400))
    #expect(secondary.localRect == CGRect(x: 120, y: 100, width: 600, height: 400))
    let local = try #require(CaptureRegion(localRect: secondary.localRect, displayBounds: secondary.displayBounds))
    #expect(local == secondary)
}

@Test func clipping() throws {
    let clipped = try region(CGRect(x: -20, y: 30, width: 80, height: 90), in: small)
    #expect(clipped.rect == CGRect(x: 0, y: 30, width: 60, height: 70))
    #expect(CaptureRegion(rect: CGRect(x: 200, y: 200, width: 30, height: 30), displayBounds: small) == nil)
}

@Test func minimumSize() {
    #expect(CaptureRegion(rect: CGRect(x: 0, y: 0, width: 4, height: 5), displayBounds: small) == nil)
}

@Test func retinaScaling() throws {
    let retina = try region(CGRect(x: 0, y: 0, width: 600, height: 400), in: laptop)
    #expect(retina.pixelSize(scale: 2, maximumWidth: 900) == CGSize(width: 900, height: 600))
    #expect(retina.pixelSize(scale: 1, maximumWidth: 1200) == CGSize(width: 600, height: 400))
}

@Test func exportOptionBounds() {
    #expect(options.fps == 30)
    #expect(options.maximumWidth == 2560)
    #expect(options.quality == 20)
}

@Test func argumentBuilding() throws {
    let output = URL(fileURLWithPath: "/tmp/a folder/output.gif")
    let arguments = options.arguments(output: output, frames: ["frame-00000.png", "frame-00001.png"])
    #expect(arguments.contains(output.path))
    #expect(arguments.contains("--fast"))
    let repeatIndex = try #require(arguments.firstIndex(of: "--repeat"))
    #expect(arguments[repeatIndex + 1] == "-1")
    #expect(arguments.suffix(3) == ["--", "frame-00000.png", "frame-00001.png"])
}

@Test func frameCountEdgeCases() {
    #expect(options.frameCount(duration: .nan) == 0)
    #expect(options.frameCount(duration: 0) == 0)
    #expect(options.frameCount(duration: 0.01) == 2)
    #expect(options.frameCount(duration: 2) == 60)
    #expect(options.frameCount(duration: 999) == 3630)
}

@Test func recoveryInfoRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Framelet-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let movie = directory.appendingPathComponent("capture.mp4")
    #expect(RecoveryInfo.url(besides: movie) == directory.appendingPathComponent("recovery.json"))
    #expect(RecoveryInfo.read(besides: movie) == nil)
    try RecoveryInfo(fps: 25).write(besides: movie)
    #expect(RecoveryInfo.read(besides: movie) == RecoveryInfo(fps: 25))
    try Data("not json".utf8).write(to: RecoveryInfo.url(besides: movie))
    #expect(RecoveryInfo.read(besides: movie) == nil)
}

@Test func lastRegionValidity() throws {
    let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let last = LastRegion(region: try region(CGRect(x: 1600, y: 100, width: 400, height: 250), in: external), displayID: 7)
    #expect(last.region(displays: [1: laptop, 7: external])?.rect == CGRect(x: 1600, y: 100, width: 400, height: 250))
    #expect(last.region(displays: [1: laptop]) == nil, "A disconnected display must be ignored")
    #expect(last.region(displays: [7: laptop]) == nil, "A display with changed geometry must be ignored")
    #expect(last.region(displays: [7: external.offsetBy(dx: -1440, dy: 0)]) == nil, "A moved display must be ignored")
    let stale = Data(#"{"rect":[[1800,900],[400,250]],"displayBounds":[[1440,0],[1920,1080]],"displayID":7}"#.utf8)
    #expect(try JSONDecoder().decode(LastRegion.self, from: stale).region(displays: [7: external]) == nil,
            "A rect that no longer fits must be ignored")
}

@Test func lastRegionPersistence() throws {
    let suiteName = "FrameletTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let last = LastRegion(region: try region(CGRect(x: 10.5, y: 20, width: 300, height: 200), in: laptop), displayID: 1)
    defaults.set(try JSONEncoder().encode(last), forKey: "lastRegion")
    let restored = try JSONDecoder().decode(LastRegion.self, from: try #require(defaults.data(forKey: "lastRegion")))
    #expect(restored == last)
    #expect(restored.region(displays: [1: laptop]) == CaptureRegion(rect: last.rect, displayBounds: laptop))
}

@Test func gifSummaryText() {
    let english = Locale(identifier: "en_US")
    #expect(GIFSummary(bytes: 1_800_000, width: 320, height: 180, duration: 4.2).text(locale: english) == "1.8 MB, 320\u{00D7}180, 4.2 s")
    #expect(GIFSummary(bytes: 532_000, width: 1280, height: 720, duration: 0.95).text(locale: english) == "532 kB, 1280\u{00D7}720, 1.0 s")
    #expect(GIFSummary(bytes: 1_800_000, width: 2, height: 2, duration: 4.26).text(locale: Locale(identifier: "de_DE")) == "1,8 MB, 2\u{00D7}2, 4,3 s")
}

@Test func gifSummaryReadsFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Framelet-test-\(UUID().uuidString).gif")
    defer { try? FileManager.default.removeItem(at: url) }
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 3, nil))
    let context = try #require(CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    let image = try #require(context.makeImage())
    for _ in 0..<3 {
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.5]] as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(destination))
    let summary = try #require(GIFSummary(contentsOf: url))
    #expect(summary.width == 40 && summary.height == 30)
    #expect(abs(summary.duration - 1.5) < 0.01)
    #expect(summary.bytes == (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize))
    #expect(GIFSummary(contentsOf: url.deletingPathExtension()) == nil)
}
