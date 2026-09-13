import Foundation

public struct ExportOptions: Sendable {
    public let fps: Int
    public let maximumWidth: Int
    public let quality: Int
    public let fast: Bool
    public let loops: Bool

    public init(fps: Int, maximumWidth: Int, quality: Int, fast: Bool, loops: Bool) {
        self.fps = min(max(fps, 5), 30)
        self.maximumWidth = min(max(maximumWidth, 320), 2560)
        self.quality = min(max(quality, 20), 100)
        self.fast = fast
        self.loops = loops
    }

    public func arguments(output: URL, frames: [String]) -> [String] {
        var arguments = [
            "--quiet", "--fps", String(fps), "--quality", String(quality),
            "--width", String(maximumWidth), "--repeat", loops ? "0" : "-1",
            "--output", output.path
        ]
        if fast { arguments.append("--fast") }
        return arguments + ["--"] + frames
    }

    public func frameCount(duration: Double) -> Int {
        guard duration.isFinite, duration > 0 else { return 0 }
        return max(2, Int((min(duration, 121) * Double(fps)).rounded(.up)))
    }
}