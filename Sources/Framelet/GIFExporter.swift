import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import RecorderCore

enum ExportStage: Sendable {
    case preparingFrames, optimizing
    var title: String { self == .preparingFrames ? "Preparing frames" : "Optimizing GIF" }
}

enum GIFExporter {
    static let encoderVersion = Bundle.main.object(forInfoDictionaryKey: "FrameletEncoderVersion") as? String

    static var bundledEncoder: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/gifski")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// A take is usable for retry only if it exists and has a video track with a positive duration.
    static func isUsableMovie(_ url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty,
              let duration = try? await asset.load(.duration) else { return false }
        return duration.seconds.isFinite && duration.seconds > 0
    }

    /// Exports `range` of the movie (the whole movie when nil); frame count and GIF timing are relative to the range start.
    static func export(
        movie: URL, directory: URL, encoder: URL, options: ExportOptions, range: CMTimeRange? = nil,
        progress: @escaping @Sendable (Double, ExportStage) async -> Void
    ) async throws -> URL {
        let fileManager = FileManager.default
        let workspace = movie.deletingLastPathComponent().appendingPathComponent("frames-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }
        let asset = AVURLAsset(url: movie)
        let full = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        let span = range.map { $0.intersection(full) } ?? full
        let start = span.start.seconds, duration = span.duration.seconds
        let count = options.frameCount(duration: duration)
        guard count > 0 else { throw RecorderError.message("The recording contains no frames. Record for a little longer and try again.") }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecorderError.message("The recording contains no video. Record again and try exporting.")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        if range != nil { reader.timeRange = span }
        guard reader.startReading() else { throw reader.error ?? RecorderError.message("The recording could not be read.") }
        defer { reader.cancelReading() }
        func nextFrame() throws -> (time: Double, image: CGImage)? {
            while true {
                let frame: (time: Double, image: CGImage?)? = autoreleasepool {
                    guard let sample = output.copyNextSampleBuffer() else { return nil }
                    return (sample.presentationTimeStamp.seconds, sample.imageBuffer.flatMap(image))
                }
                guard let frame else { break }
                if let image = frame.image { return (frame.time, image) }
            }
            if reader.status == .failed { throw reader.error ?? RecorderError.message("The recording could not be read.") }
            return nil
        }
        var upcoming = try nextFrame()
        var current: CGImage?
        var frames: [String] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let seconds = start + min(Double(index) / Double(options.fps), max(0, duration - 1.0 / Double(options.fps)))
            while let candidate = upcoming, current == nil || candidate.time <= seconds + 0.0005 {
                current = candidate.image
                upcoming = try nextFrame()
            }
            guard let frame = current else { throw RecorderError.message("The recording contains no frames. Record for a little longer and try again.") }
            let name = String(format: "frame-%05d.png", index)
            let url = workspace.appendingPathComponent(name)
            try autoreleasepool {
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    throw RecorderError.message("Could not create a temporary frame. Check available disk space.")
                }
                CGImageDestinationAddImage(destination, frame, nil)
                guard CGImageDestinationFinalize(destination) else {
                    throw RecorderError.message("Writing a frame failed. Check available disk space.")
                }
            }
            frames.append(name)
            if index % 5 == 0 { await progress(Double(index + 1) / Double(count), .preparingFrames) }
        }
        try Task.checkCancellation()
        await progress(1, .optimizing)
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

    private static func image(_ buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let provider = CGDataProvider(data: Data(bytes: base, count: bytesPerRow * CVPixelBufferGetHeight(buffer)) as CFData) else { return nil }
        return CGImage(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
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