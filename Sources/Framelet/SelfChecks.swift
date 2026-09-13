import AppKit
import AVFoundation
import ImageIO
import RecorderCore

@MainActor
enum SelfChecks {
    static func run() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try await ScreenRecorder.checkSystemStop()
        guard let encoder = GIFExporter.bundledEncoder else { throw RecorderError.message("Run --self-test from the built .app bundle.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Framelet-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let movie = directory.appendingPathComponent("test.mp4")
        try await makeMovie(at: movie)
        let outputDirectory = directory.appendingPathComponent("output with spaces", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let options = ExportOptions(fps: 10, maximumWidth: 320, quality: 80, fast: false, loops: true)
        let first = try await GIFExporter.export(movie: movie, directory: outputDirectory, encoder: encoder, options: options) { _, _ in }
        try inspectGIF(first, loops: true)
        print("PASS: real MP4 -> PNG -> bundled gifski -> animated GIF (320 x 180, 10 fps, 2 seconds, looping)")

        let second = try await GIFExporter.export(movie: movie, directory: outputDirectory, encoder: encoder, options: options) { _, _ in }
        try require(first != second, "Exports must not overwrite one another")
        try require(FileManager.default.fileExists(atPath: first.path), "Original GIF must be retained")
        print("PASS: paths with spaces and collision-safe output names")

        let once = ExportOptions(fps: 10, maximumWidth: 320, quality: 65, fast: true, loops: false)
        let third = try await GIFExporter.export(movie: movie, directory: outputDirectory, encoder: encoder, options: once) { _, _ in }
        try inspectGIF(third, loops: false)
        print("PASS: single-play GIF and fast encoding")

        let cancelled = Task {
            try await GIFExporter.export(movie: movie, directory: outputDirectory, encoder: encoder, options: options) { _, _ in }
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            throw RecorderError.message("Cancelled export unexpectedly succeeded")
        } catch is CancellationError {}
        try require(FileManager.default.fileExists(atPath: movie.path), "Cancellation must preserve the original movie")
        let remaining = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        try require(!remaining.contains(where: { $0.lastPathComponent.hasPrefix("frames-") }), "Temporary frames must be cleaned up")
        print("PASS: cancellation preserves original and removes temporary frames")

        do {
            _ = try await GIFExporter.export(movie: movie, directory: directory.appendingPathComponent("missing/folder"), encoder: encoder, options: options) { _, _ in }
            throw RecorderError.message("Export to a missing destination unexpectedly succeeded")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain {}
        try require(FileManager.default.fileExists(atPath: movie.path), "Destination failure must preserve the original")
        print("PASS: destination failure preserves original for retry")

        let suiteName = "FrameletChecks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        try require(settings.shortcut == .defaultShortcut, "Default shortcut must be Command-Shift-8")
        settings.fps = 20
        settings.quality = 65
        try settings.setDirectory(outputDirectory)
        let restored = AppSettings(defaults: defaults)
        try require(restored.fps == 20 && restored.quality == 65, "Export preferences must persist")
        try require(restored.outputDirectory.standardizedFileURL == outputDirectory.standardizedFileURL, "Folder bookmark must persist")
        print("PASS: default shortcut, settings persistence, output folder bookmark")

        let snapshots = ProcessInfo.processInfo.environment["FRAMELET_TEST_ARTIFACTS"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? directory
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try RegionSelector.checkInteractions(snapshots: snapshots)
    }

    private static func inspectGIF(_ url: URL, loops: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let properties = CGImageSourceCopyProperties(source, nil) as? [String: Any] else {
            throw RecorderError.message("GIF cannot be decoded")
        }
        try require(image.width == 320 && image.height == 180, "GIF has unexpected dimensions")
        let count = CGImageSourceGetCount(source)
        try require(count >= 18 && count <= 21, "GIF must contain the animation's frames; got \(count)")
        let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        let repeatCount = gif?[kCGImagePropertyGIFLoopCount as String] as? Int
        try require(loops ? repeatCount == 0 : repeatCount != 0, "GIF loop metadata is incorrect")
        var duration = 0.0
        for index in 0..<count {
            let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
            let frameGIF = frameProperties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            duration += frameGIF?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
                ?? frameGIF?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0
        }
        try require(abs(duration - 2) <= 0.15, "GIF duration is \(duration), expected 2 seconds")
    }

    private static func makeMovie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320, AVVideoHeightKey: 180
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        writer.add(input)
        try require(writer.startWriting(), "Could not start fixture writer")
        writer.startSession(atSourceTime: .zero)
        for index in 0..<20 {
            let deadline = Date().addingTimeInterval(10)
            while !input.isReadyForMoreMediaData {
                try require(writer.status == .writing && Date() < deadline, "Fixture writer stalled")
                await Task.yield()
            }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool else { throw RecorderError.message("Missing pixel buffer pool") }
            try require(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, "Could not create fixture pixel buffer")
            guard let buffer else { throw RecorderError.message("Missing fixture pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180,
                                          bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
                CVPixelBufferUnlockBaseAddress(buffer, [])
                throw RecorderError.message("Could not draw fixture frame")
            }
            context.setFillColor(CGColor(red: 0.91, green: 0.96, blue: 0.94, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            context.setFillColor(CGColor(red: 0.92, green: 0.16, blue: 0.20, alpha: 1))
            context.fillEllipse(in: CGRect(x: 12 + index * 12, y: 62, width: 44, height: 44))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try require(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 10)), "Could not append fixture frame")
        }
        writer.endSession(atSourceTime: CMTime(value: 2, timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        try require(writer.status == .completed, "Fixture writer failed: \(writer.error?.localizedDescription ?? "unknown")")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw RecorderError.message(message) }
    }
}