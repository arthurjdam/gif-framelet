import Foundation
import CoreGraphics
import Testing
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
