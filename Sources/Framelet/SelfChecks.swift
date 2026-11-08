import AppKit
import AVFoundation
import ImageIO
import RecorderCore
import Synchronization

@MainActor
enum SelfChecks {
    static func run() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try await ScreenRecorder.checkSystemStop()
        try await ScreenRecorder.checkCancelDuringStart()
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

        let long = directory.appendingPathComponent("long.mp4")
        try await makeMovie(at: long, frames: 300, fps: 30)
        let clock = ContinuousClock()
        let start = clock.now
        let extracted = Mutex<ContinuousClock.Instant?>(nil)
        let timed = try await GIFExporter.export(movie: long, directory: outputDirectory, encoder: encoder,
                                                 options: ExportOptions(fps: 30, maximumWidth: 320, quality: 80, fast: false, loops: true)) { progress, _ in
            if progress >= 1 { extracted.withLock { $0 = $0 ?? clock.now } }
        }
        let seconds = { (duration: Duration) in duration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2))) }
        let total = clock.now - start
        let frames = CGImageSourceCreateWithURL(timed as CFURL, nil).map(CGImageSourceGetCount) ?? 0
        try require(frames >= 290 && frames <= 301, "Long GIF must contain its frames; got \(frames)")
        print("PASS: 10 s @ 30 fps export (\(frames) frames) in \(seconds(total)), frame extraction \(seconds((extracted.withLock { $0 } ?? start) - start))")

        try require(RecoveryInfo.read(besides: movie) == nil, "A missing recovery sidecar must read as nil")
        try RecoveryInfo(fps: 25).write(besides: movie)
        try require(RecoveryInfo.read(besides: movie) == RecoveryInfo(fps: 25), "Recovery sidecar must round-trip the capture fps")
        try Data("not json".utf8).write(to: RecoveryInfo.url(besides: movie))
        try require(RecoveryInfo.read(besides: movie) == nil, "A corrupt recovery sidecar must read as nil")
        print("PASS: recovery sidecar write/read round-trip")

        let take = { (name: String, contents: Data?) throws -> URL in
            let folder = directory.appendingPathComponent("Framelet-\(name)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("capture.mp4")
            if let contents { try contents.write(to: url) }
            return url
        }
        let previous = try take("previous", Data(contentsOf: movie))
        for (name, contents) in [("empty", Data()), ("garbage", Data("not a movie".utf8)), ("missing", nil)] as [(String, Data?)] {
            let unusable = try take(name, contents)
            let kept = await AppController.recovery(replacing: previous, with: unusable)
            try require(kept == previous, "An unusable \(name) take must keep the previous recovery")
            try require(FileManager.default.fileExists(atPath: previous.path), "An unusable \(name) take must not delete the previous recovery")
            try require(!FileManager.default.fileExists(atPath: unusable.deletingLastPathComponent().path), "An unusable \(name) take must be removed")
        }
        let lone = await AppController.recovery(replacing: nil, with: try take("lone", Data()))
        try require(lone == nil, "An unusable take must not become the recovery")
        let replacement = try take("replacement", Data(contentsOf: movie))
        let replaced = await AppController.recovery(replacing: previous, with: replacement)
        try require(replaced == replacement, "A usable take must replace the recovery")
        try require(!FileManager.default.fileExists(atPath: previous.path), "Replacing must delete the previous recovery")
        print("PASS: unusable new take keeps the previous recovery; usable take replaces it")

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

        let locked = directory.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o555])
        try require(FolderStatus(of: outputDirectory) == .ok, "A writable folder must validate")
        try require(FolderStatus(of: directory.appendingPathComponent("missing")) == .missing, "A missing folder must be reported")
        try require(FolderStatus(of: movie) == .notDirectory, "A file is not an output folder")
        try require(FolderStatus(of: locked) == .notWritable, "A read-only folder must be reported")
        let discarded = directory.appendingPathComponent("trashed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: discarded, withIntermediateDirectories: false)
        var trashed: NSURL?
        try FileManager.default.trashItem(at: discarded, resultingItemURL: &trashed)
        defer { if let trashed { try? FileManager.default.removeItem(at: trashed as URL) } }
        try require((trashed as URL?).map { FolderStatus(of: $0) } == .inTrash, "A folder in the Trash must be reported")
        let chosen = directory.appendingPathComponent("chosen", isDirectory: true)
        let moved = directory.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: false)
        try settings.setDirectory(chosen)
        let original = defaults.data(forKey: "outputBookmark")
        try FileManager.default.moveItem(at: chosen, to: moved)
        let relocated = AppSettings(defaults: defaults)
        try require(relocated.outputDirectory.resolvingSymlinksInPath() == moved.resolvingSymlinksInPath(), "A moved folder must resolve")
        try require(defaults.data(forKey: "outputBookmark") != original, "A stale bookmark must be refreshed and persisted")
        try FileManager.default.removeItem(at: moved)
        let gone = AppSettings(defaults: defaults)
        try require(gone.outputDirectory.lastPathComponent == "moved" && gone.outputDirectory.deletingLastPathComponent()
                        .resolvingSymlinksInPath() == directory.resolvingSymlinksInPath(),
                    "A deleted folder must be kept, not replaced by Desktop; got \(gone.outputDirectory.path)")
        try require(gone.outputStatus == .missing, "A deleted folder must be reported missing")
        try require(gone.outputProblem?.contains(gone.outputDirectory.path(percentEncoded: false)) == true, "The problem must name the folder")
        print("PASS: output folder validation, stale bookmark refresh, missing folder reported")

        let snapshots = ProcessInfo.processInfo.environment["FRAMELET_TEST_ARTIFACTS"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? directory
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try RegionSelector.checkInteractions(snapshots: snapshots)
    }

    private static func inspectGIF(_ url: URL, loops: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyProperties(source, nil) as? [String: Any],
              let summary = GIFSummary(contentsOf: url) else {
            throw RecorderError.message("GIF cannot be decoded")
        }
        try require(summary.width == 320 && summary.height == 180, "GIF has unexpected dimensions")
        let count = CGImageSourceGetCount(source)
        try require(count >= 18 && count <= 21, "GIF must contain the animation's frames; got \(count)")
        let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        let repeatCount = gif?[kCGImagePropertyGIFLoopCount as String] as? Int
        try require(loops ? repeatCount == 0 : repeatCount != 0, "GIF loop metadata is incorrect")
        try require(abs(summary.duration - 2) <= 0.15, "GIF duration is \(summary.duration), expected 2 seconds")
        try require(summary.bytes > 0 && summary.text().contains("320\u{00D7}180"), "GIF summary is incomplete: \(summary.text())")
    }

    private static func makeMovie(at url: URL, frames: Int = 20, fps: Int = 10) async throws {
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
        for index in 0..<frames {
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
            context.fillEllipse(in: CGRect(x: 12 + index % 20 * 12, y: 62, width: 44, height: 44))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try require(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: CMTimeScale(fps))), "Could not append fixture frame")
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(frames), timescale: CMTimeScale(fps)))
        input.markAsFinished()
        await writer.finishWriting()
        try require(writer.status == .completed, "Fixture writer failed: \(writer.error?.localizedDescription ?? "unknown")")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw RecorderError.message(message) }
    }
}