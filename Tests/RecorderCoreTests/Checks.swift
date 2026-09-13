import Foundation
import CoreGraphics
import RecorderCore

@main
struct Checks {
    static func main() throws {
        let primary = try region(
            CGRect(x: 100, y: 200, width: 300, height: 180),
            in: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        precondition(primary.sourceRect == CGRect(x: 100, y: 520, width: 300, height: 180))

        let secondary = try region(
            CGRect(x: -1800, y: 1000, width: 600, height: 400),
            in: CGRect(x: -1920, y: 900, width: 1920, height: 1080)
        )
        precondition(secondary.sourceRect == CGRect(x: 120, y: 580, width: 600, height: 400))

        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let clipped = try region(CGRect(x: -20, y: 30, width: 80, height: 90), in: bounds)
        precondition(clipped.rect == CGRect(x: 0, y: 30, width: 60, height: 70))
        precondition(CaptureRegion(rect: CGRect(x: 0, y: 0, width: 4, height: 5), displayBounds: bounds) == nil)
        precondition(CaptureRegion(rect: CGRect(x: 200, y: 200, width: 30, height: 30), displayBounds: bounds) == nil)

        let retina = try region(
            CGRect(x: 0, y: 0, width: 600, height: 400),
            in: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        precondition(retina.pixelSize(scale: 2, maximumWidth: 900) == CGSize(width: 900, height: 600))
        precondition(retina.pixelSize(scale: 1, maximumWidth: 1200) == CGSize(width: 600, height: 400))
        print("PASS: coordinate conversion, secondary displays, clipping, minimum size, Retina scaling")

        let options = ExportOptions(fps: 100, maximumWidth: 9999, quality: 0, fast: true, loops: false)
        precondition(options.fps == 30 && options.maximumWidth == 2560 && options.quality == 20)
        let output = URL(fileURLWithPath: "/tmp/a folder/output.gif")
        let arguments = options.arguments(output: output, frames: ["frame-00000.png", "frame-00001.png"])
        precondition(arguments.contains(output.path))
        precondition(arguments.contains("--fast"))
        precondition(arguments[arguments.firstIndex(of: "--repeat")! + 1] == "-1")
        precondition(arguments.suffix(3) == ["--", "frame-00000.png", "frame-00001.png"])
        precondition(options.frameCount(duration: .nan) == 0)
        precondition(options.frameCount(duration: 0) == 0)
        precondition(options.frameCount(duration: 0.01) == 2)
        precondition(options.frameCount(duration: 2) == 60)
        precondition(options.frameCount(duration: 999) == 3630)
        print("PASS: export bounds, argument boundaries, loop settings, short and invalid durations")
    }

    static func region(_ rect: CGRect, in bounds: CGRect) throws -> CaptureRegion {
        guard let region = CaptureRegion(rect: rect, displayBounds: bounds) else {
            throw NSError(domain: "FrameletChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected a valid region"])
        }
        return region
    }
}