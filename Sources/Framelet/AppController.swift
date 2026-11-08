import AppKit
import SwiftUI
import RecorderCore

@MainActor
final class AppController: ObservableObject {
    enum Phase { case idle, selecting, starting, recording, stopping, exporting, failed }
    let settings = AppSettings()
    let shortcut = GlobalShortcut()
    private let selector = RegionSelector()
    private var recorder: ScreenRecorder?
    private var settingsWindow: NSWindow?
    private var timer: Timer?
    private var startedAt: Date?
    private var exportTask: Task<Void, Never>?
    private var cancellingStart = false
    @Published private(set) var phase = Phase.idle {
        didSet {
            // The discard hot key exists only while recording; every exit from .recording goes through here.
            guard (phase == .recording) != (oldValue == .recording) else { return }
            if phase == .recording { try? shortcut.registerDiscard(settings.shortcut) } else { shortcut.unregisterDiscard() }
        }
    }
    @Published private(set) var hasPermission = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var exportProgress = 0.0
    @Published private(set) var exportStage = ExportStage.preparingFrames
    @Published private(set) var errorMessage: String?
    @Published private(set) var recoveryMovie: URL?
    @Published private(set) var lastExport: URL?
    @Published private(set) var editingShortcut = false

    var elapsedText: String { String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60) }
    var isBusy: Bool { ![.idle, .failed].contains(phase) }
    var statusText: String {
        switch phase {
        case .idle: hasPermission ? "Ready to record" : "Screen Recording permission needed"
        case .selecting: "Selecting a region"
        case .starting: "Starting recording"
        case .recording: "Recording \(elapsedText)"
        case .stopping: "Finishing recording"
        case .exporting: exportStage == .preparingFrames ? "\(exportStage.title) \(Int(exportProgress * 100))%" : exportStage.title
        case .failed: recoveryMovie == nil ? "Recording unavailable" : "Recording saved for retry"
        }
    }

    func launch() {
        shortcut.onPress = { [weak self] in self?.trigger() }
        shortcut.onDiscard = { [weak self] in self?.discard() }
        selector.onCancel = { [weak self] in self?.cancelSelection() }
        selector.onRecord = { [weak self] region, screen in self?.start(region: region, screen: screen) }
        do { try shortcut.register(settings.shortcut) } catch { errorMessage = error.localizedDescription }
        let interrupt: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.interruptCapture() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: interrupt)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: interrupt)
        restoreRecovery()
        if !ensurePermission() { showSettings() }
    }

    func refreshPermission() { hasPermission = CGPreflightScreenCaptureAccess() }

    @discardableResult
    func ensurePermission() -> Bool {
        refreshPermission()
        if !hasPermission { hasPermission = CGRequestScreenCaptureAccess() }
        if !hasPermission {
            errorMessage = "Allow Framelet in System Settings > Privacy & Security > Screen & System Audio Recording. If macOS asks you to quit and reopen Framelet, do so before recording."
        }
        return hasPermission
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }

    func trigger() {
        guard !editingShortcut else { return }
        switch phase {
        case .starting, .recording: stop()
        case .selecting: cancelSelection()
        case .idle, .failed:
            guard ensurePermission() else { showSettings(); return }
            guard GIFExporter.bundledEncoder != nil else {
                fail("The bundled GIF encoder is missing. Build and launch Framelet.app with scripts/build-app.sh, not swift run.")
                showSettings()
                return
            }
            guard recoveryMovie == nil || confirmReplacingRecovery() else { return }
            errorMessage = nil
            phase = .selecting
            settingsWindow?.orderOut(nil)
            selector.show(maximumWidth: settings.maximumWidth)
        case .stopping, .exporting: break
        }
    }

    /// Framelet keeps one recovery. Asked before the selector opens; the previous take is only deleted once a new movie exists.
    private func confirmReplacingRecovery() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Keep previous recording for retry?"
        alert.informativeText = "Framelet keeps one recording for retry. The previous recording is deleted once the new one is captured. To keep it, reveal it and copy it elsewhere before recording."
        alert.addButton(withTitle: "Record and Replace")
        alert.addButton(withTitle: "Reveal Previous")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: revealRecovery(); return false
        default: return false
        }
    }

    func cancelSelection() {
        guard phase == .selecting else { return }
        selector.close()
        phase = restingPhase
    }

    private func start(region: CaptureRegion, screen: NSScreen) {
        guard phase == .selecting else { return }
        phase = .starting
        let options = settings.exportOptions
        let recorder = ScreenRecorder()
        self.recorder = recorder
        recorder.onStopRequested = { [weak self] in self?.stop() }
        recorder.onUnexpectedStop = { [weak self, weak recorder] error in
            guard let self, let recorder, self.recorder === recorder, self.phase == .recording || self.phase == .starting else { return }
            self.timer?.invalidate()
            self.selector.close()
            if self.phase == .starting {
                // begin() stops the capture and deletes the take; the start task's catch then leaves this error in place.
                recorder.cancel()
                self.fail(error.localizedDescription)
                return
            }
            self.phase = .stopping
            Task {
                _ = try? await recorder.stop()
                if let movie = recorder.movieURL { _ = await self.keepForRetry(movie) }
                self.recorder = nil
                self.fail(error.localizedDescription)
            }
        }
        selector.setRecording(dimOutside: settings.dimOutside)
        Task {
            do {
                try await recorder.start(region: region, screen: screen, fps: options.fps, maximumWidth: options.maximumWidth, showsCursor: settings.showsCursor)
                if let movie = recorder.movieURL { try? RecoveryInfo(fps: options.fps).write(besides: movie) }
                guard phase == .starting, self.recorder === recorder else {
                    await recorder.discard()
                    guard self.recorder === recorder else { return }
                    self.recorder = nil
                    cancellingStart = false
                    if phase == .stopping { phase = restingPhase }
                    return
                }
                phase = .recording
                elapsed = 0
                startedAt = Date()
                let limit = settings.maximumDuration
                let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        guard let startedAt = self.startedAt else { return }
                        self.elapsed = Date().timeIntervalSince(startedAt)
                        if self.elapsed >= Double(limit) { self.stop() }
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            } catch is CancellationError {
                guard self.recorder === recorder else { return }
                self.recorder = nil
                cancellingStart = false
                if phase == .stopping { phase = restingPhase }
            } catch {
                guard self.recorder === recorder else { return }
                selector.close()
                self.recorder = nil
                fail(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard phase == .recording || phase == .starting, let recorder else { return }
        if phase == .starting {
            phase = .stopping
            cancellingStart = true
            selector.close()
            recorder.cancel()
            return
        }
        phase = .stopping
        timer?.invalidate()
        timer = nil
        selector.close()
        Task {
            do {
                let movie = try await recorder.stop()
                self.recorder = nil
                guard await keepForRetry(movie) else {
                    fail("The recording contains no usable video." + (recoveryMovie == nil ? " Record for a little longer and try again." : " The previous recording is still available for retry."))
                    return
                }
                export(movie)
            } catch {
                if let movie = recorder.movieURL { _ = await keepForRetry(movie) }
                self.recorder = nil
                fail(error.localizedDescription)
            }
        }
    }

    /// Stops capture and deletes the take without exporting or touching the recovery (no keepForRetry).
    /// Before recording begins (.starting, and a countdown) it is stop()'s cancel path; stop() ignores other phases.
    /// A system stop or the time limit can't export the take meanwhile: stop() requires .recording and the timer is gone.
    func discard() {
        guard phase == .recording, let recorder else { stop(); return }
        phase = .stopping
        timer?.invalidate()
        timer = nil
        selector.close()
        Task {
            _ = try? await recorder.stop()
            if let movie = recorder.movieURL { Self.removeTake(movie) }
            self.recorder = nil
            phase = restingPhase
        }
    }

    private var restingPhase: Phase { recoveryMovie == nil ? .idle : .failed }

    /// Makes a new take the single recovery (the user agreed to replace any previous one in trigger()),
    /// but only if it is usable; otherwise the new take is deleted and the previous recovery is kept.
    private func keepForRetry(_ movie: URL) async -> Bool {
        guard movie != recoveryMovie else { return true }
        guard await Self.recovery(replacing: recoveryMovie, with: movie) == movie else { return false }
        recoveryMovie = movie
        UserDefaults.standard.set(movie.path, forKey: "recoveryMovie")
        return true
    }

    /// Returns the take to keep for retry: `new` if it is a usable movie (deleting `old`), else `old` (deleting `new`).
    nonisolated static func recovery(replacing old: URL?, with new: URL) async -> URL? {
        guard await GIFExporter.isUsableMovie(new) else { removeTake(new); return old }
        if let old, old != new { removeTake(old) }
        return new
    }

    nonisolated static func removeTake(_ movie: URL) {
        let directory = movie.deletingLastPathComponent()
        if directory.lastPathComponent.hasPrefix("Framelet-") { try? FileManager.default.removeItem(at: directory) }
    }

    func retryExport() {
        guard !isBusy, let movie = recoveryMovie else { return }
        export(movie)
    }

    private func export(_ movie: URL) {
        guard let encoder = GIFExporter.bundledEncoder else { fail("The bundled gifski encoder is missing."); return }
        settings.refreshOutputStatus()
        if let problem = settings.outputProblem {
            fail(problem)
            Task { self.offerDirectoryChoice(problem) }
            return
        }
        phase = .exporting
        errorMessage = nil
        exportProgress = 0
        exportStage = .preparingFrames
        let outputDirectory = settings.outputDirectory
        let selected = settings.exportOptions
        let fps = RecoveryInfo.read(besides: movie)?.fps ?? selected.fps
        let options = ExportOptions(fps: fps, maximumWidth: selected.maximumWidth,
                                    quality: selected.quality, fast: selected.fast, loops: selected.loops)
        exportTask = Task {
            do {
                let url = try await GIFExporter.export(movie: movie, directory: outputDirectory, encoder: encoder, options: options) { progress, stage in
                    await MainActor.run {
                        self.exportProgress = progress
                        self.exportStage = stage
                    }
                }
                lastExport = url
                removeRecovery()
                phase = .idle
                exportTask = nil
                if settings.revealAfterExport { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } catch is CancellationError {
                fail("Export cancelled. The original recording is available for retry.")
                exportTask = nil
            } catch {
                settings.refreshOutputStatus()
                fail(settings.outputProblem ?? error.localizedDescription)
                exportTask = nil
            }
        }
    }

    private func offerDirectoryChoice(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Framelet can't save the GIF"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Choose Folder...")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            showSettings()
            chooseDirectory()
        }
    }

    func cancelExport() { exportTask?.cancel() }
    func revealRecovery() { if let recoveryMovie { NSWorkspace.shared.activateFileViewerSelecting([recoveryMovie]) } }

    func discardRecovery() {
        guard !isBusy else { return }
        let alert = NSAlert()
        alert.messageText = "Discard this recording?"
        alert.informativeText = "The temporary original will be deleted. This cannot be undone."
        alert.addButton(withTitle: "Keep Recording")
        alert.addButton(withTitle: "Discard")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn {
            removeRecovery()
            errorMessage = nil
            phase = .idle
        }
    }

    private func restoreRecovery() {
        guard let path = UserDefaults.standard.string(forKey: "recoveryMovie") else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            recoveryMovie = url
            phase = .failed
            errorMessage = "An unfinished export is available. Retry it or reveal the original recording."
        } else {
            UserDefaults.standard.removeObject(forKey: "recoveryMovie")
        }
    }

    private func removeRecovery() {
        if let recoveryMovie { Self.removeTake(recoveryMovie) }
        recoveryMovie = nil
        UserDefaults.standard.removeObject(forKey: "recoveryMovie")
    }

    private func interruptCapture() {
        if phase == .selecting { cancelSelection() }
        if phase == .recording || phase == .starting { stop() }
    }

    private func fail(_ message: String) { errorMessage = message; phase = .failed }

    func showError(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Framelet couldn't complete the operation"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    func showSettings() {
        settings.refreshOutputStatus()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 540),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Framelet Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(controller: self, settings: settings))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.outputDirectory
        panel.prompt = "Choose"
        guard let window = settingsWindow else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try self?.settings.setDirectory(url) } catch { self?.showError(error.localizedDescription) }
        }
    }

    func beginShortcutEditing() { editingShortcut = true; shortcut.unregister(); shortcut.unregisterDiscard() }

    func endShortcutEditing(_ value: Shortcut?) {
        editingShortcut = false
        do {
            try shortcut.register(value ?? settings.shortcut)
            if let value { settings.setShortcut(value) }
        } catch {
            try? shortcut.register(settings.shortcut)
            showError(error.localizedDescription)
        }
    }

    func canQuit() -> Bool {
        if phase == .selecting { cancelSelection() }
        guard [.starting, .recording, .stopping, .exporting].contains(phase), !(phase == .stopping && cancellingStart) else { return true }
        let alert = NSAlert()
        alert.messageText = phase == .exporting ? "A GIF is still being exported" : "A recording is in progress"
        alert.informativeText = switch phase {
        case .recording: "Stop the recording before quitting Framelet."
        case .starting: "Capture is still starting. Cancel it to quit now, or keep Framelet open."
        case .exporting: "Wait for the export to finish, or cancel it from the menu bar."
        default: "Wait for the recording to finish saving."
        }
        alert.addButton(withTitle: "Keep Framelet Open")
        if phase == .recording { alert.addButton(withTitle: "Stop Recording") }
        if phase == .starting { alert.addButton(withTitle: "Cancel and Quit") }
        NSApp.activate()
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        stop()
        return cancellingStart || !isBusy
    }
}