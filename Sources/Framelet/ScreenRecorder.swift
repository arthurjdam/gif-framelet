import AppKit
import AVFoundation
import ScreenCaptureKit
import RecorderCore

@MainActor
final class ScreenRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var completion: CheckedContinuation<URL, any Error>?
    private var finishedURL: URL?
    private var recordingError: (any Error)?
    private(set) var movieURL: URL?
    private var failureReported = false
    private var stoppedByUser = false
    private var stopRequested = false
    private var stopNotified = false
    var onStopRequested: (() -> Void)?
    var onUnexpectedStop: ((any Error) -> Void)?

    func start(region: CaptureRegion, screen: NSScreen, fps: Int, maximumWidth: Int, showsCursor: Bool) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == screenID }) else {
            throw RecorderError.message("The selected display is no longer connected.")
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let size = region.pixelSize(scale: screen.backingScaleFactor, maximumWidth: maximumWidth)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = region.sourceRect
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.showsCursor = showsCursor
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Framelet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("capture.mp4")
        movieURL = url
        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = url
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addRecordingOutput(output)
            self.stream = stream
            self.output = output
            try await stream.startCapture()
        } catch {
            self.stream = nil
            self.output = nil
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func stop() async throws -> URL {
        stopRequested = true
        guard stream != nil || stoppedByUser || finishedURL != nil else {
            throw RecorderError.message("No recording is active.")
        }
        if !stoppedByUser, let stream {
            do { try await stream.stopCapture() } catch {
                if !stoppedByUser && recordingError == nil && finishedURL == nil { recordingError = error }
            }
        }
        defer { self.stream = nil; output = nil }
        if let recordingError { throw recordingError }
        if let finishedURL { return finishedURL }
        return try await withCheckedThrowingContinuation { completion = $0 }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in self?.finishedRecording() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in self?.failed(error) }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in self?.streamStopped(with: error) }
    }

    private func streamStopped(with error: any Error) {
        let streamError = error as NSError
        if streamError.domain == SCStreamErrorDomain && streamError.code == SCStreamError.Code.userStopped.rawValue {
            stoppedByUser = true
            notifyStop()
        } else {
            failed(error)
        }
    }

    private func finishedRecording() {
        guard let movieURL else { return }
        finishedURL = movieURL
        completion?.resume(returning: movieURL)
        completion = nil
        notifyStop()
    }

    private func notifyStop() {
        guard !stopRequested, !stopNotified, recordingError == nil else { return }
        stopNotified = true
        onStopRequested?()
    }

    private func failed(_ error: any Error) {
        guard !failureReported else { return }
        failureReported = true
        recordingError = error
        completion?.resume(throwing: error)
        completion = nil
        onUnexpectedStop?(error)
    }
}

extension ScreenRecorder {
    static func checkSystemStop() async throws {
        let url = URL(fileURLWithPath: "/tmp/framelet-stop-check.mp4")
        let userStop = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userStopped.rawValue)
        for finishFirst in [false, true] {
            let recorder = ScreenRecorder()
            recorder.movieURL = url
            var notifications = 0
            var failures = 0
            recorder.onStopRequested = { notifications += 1 }
            recorder.onUnexpectedStop = { _ in failures += 1 }
            if finishFirst { recorder.finishedRecording() }
            recorder.streamStopped(with: userStop)
            if !finishFirst { recorder.finishedRecording() }
            recorder.streamStopped(with: userStop)
            let result = try await recorder.stop()
            guard result == url, notifications == 1, failures == 0 else {
                throw RecorderError.message("System stop must finalize successfully and notify once in either callback order")
            }
        }
        let pending = ScreenRecorder()
        pending.movieURL = url
        pending.streamStopped(with: userStop)
        let finalization = Task { try await pending.stop() }
        let deadline = Date().addingTimeInterval(5)
        while pending.completion == nil && Date() < deadline { await Task.yield() }
        guard pending.completion != nil else { throw RecorderError.message("Stop did not wait for movie finalization") }
        pending.finishedRecording()
        guard try await finalization.value == url else {
            throw RecorderError.message("System stop must wait for movie finalization")
        }
        let appStopped = ScreenRecorder()
        appStopped.movieURL = url
        appStopped.stopRequested = true
        var duplicateStop = false
        appStopped.onStopRequested = { duplicateStop = true }
        appStopped.finishedRecording()
        guard !duplicateStop else { throw RecorderError.message("App-initiated stop must not trigger a second stop") }
        let failed = ScreenRecorder()
        var reportedFailure = false
        failed.onUnexpectedStop = { _ in reportedFailure = true }
        failed.streamStopped(with: NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.internalError.rawValue))
        guard reportedFailure else { throw RecorderError.message("Real stream errors must remain failures") }
        print("PASS: native stop callback ordering, deduplication, movie finalization, and stream errors")
    }
}

enum RecorderError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}