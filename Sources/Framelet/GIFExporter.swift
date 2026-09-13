import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import RecorderCore

enum GIFExporter {
    static var bundledEncoder: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/gifski")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func export(
        movie: URL, directory: URL, encoder: URL, options: ExportOptions,
        progress: @escaping @Sendable (Double, String) async -> Void
    ) async throws -> URL {
        let fileManager = FileManager.default
        let workspace = movie.deletingLastPathComponent().appendingPathComponent("frames-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }
        let asset = AVURLAsset(url: movie)
        let duration = try await asset.load(.duration).seconds
        let count = options.frameCount(duration: duration)
        guard count > 0 else { throw RecorderError.message("The recording contains no frames. Record for a little longer and try again.") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: CMTimeScale(options.fps * 2))
        generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
        var frames: [String] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let seconds = min(Double(index) / Double(options.fps), max(0, duration - 1.0 / Double(options.fps)))
            let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            let name = String(format: "frame-%05d.png", index)
            let url = workspace.appendingPathComponent(name)
            try autoreleasepool {
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    throw RecorderError.message("Could not create a temporary frame. Check available disk space.")
                }
                CGImageDestinationAddImage(destination, frame.image, nil)
                guard CGImageDestinationFinalize(destination) else {
                    throw RecorderError.message("Writing a frame failed. Check available disk space.")
                }
            }
            frames.append(name)
            if index % 5 == 0 { await progress(Double(index + 1) / Double(count), "Preparing frames") }
        }
        try Task.checkCancellation()
        await progress(1, "Optimizing GIF")
        let encoded = workspace.appendingPathComponent("output.gif")
        try await encode(encoder: encoder, options: options, workspace: workspace, output: encoded, frames: frames)
        try Task.checkCancellation()
        let timestamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted))
            .replacingOccurrences(of: ":", with: "-")
        let destination = directory.appendingPathComponent("Framelet-\(timestamp)-\(UUID().uuidString.prefix(6)).gif")
        let staging = directory.appendingPathComponent(".framelet-\(UUID().uuidString).gif")
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: encoded, to: staging)
        try fileManager.moveItem(at: staging, to: destination)
        return destination
    }

    private static func encode(encoder: URL, options: ExportOptions, workspace: URL, output: URL, frames: [String]) async throws {
        let process = Process()
        let log = workspace.appendingPathComponent("encoder.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: log)
        defer { try? logHandle.close() }
        process.executableURL = encoder
        process.currentDirectoryURL = workspace
        process.arguments = options.arguments(output: output, frames: frames)
        process.standardOutput = logHandle
        process.standardError = logHandle
        let exitCode: Int32 = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
                do {
                    try process.run()
                    if Task.isCancelled && process.isRunning { process.terminate() }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        guard exitCode == 0 else {
            let details = (try? String(contentsOf: log, encoding: .utf8)) ?? "Exit code \(exitCode)"
            throw RecorderError.message("GIF optimization failed. \(details.prefix(700))")
        }
    }
}