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
    private var recordingOptions: ExportOptions?
    private var observers: [NSObjectProtocol] = []
    @Published private(set) var phase = Phase.idle
    @Published private(set) var hasPermission = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var exportProgress = 0.0
    @Published private(set) var exportStage = "Preparing frames"
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
        case .exporting: exportStage == "Preparing frames" ? "Preparing frames \(Int(exportProgress * 100))%" : exportStage
        case .failed: recoveryMovie == nil ? "Recording unavailable" : "Recording saved for retry"
        }
    }

    func launch() {
        shortcut.onPress = { [weak self] in self?.trigger() }
        selector.onCancel = { [weak self] in self?.cancelSelection() }
        selector.onRecord = { [weak self] region, screen in self?.start(region: region, screen: screen) }
        do { try shortcut.register(settings.shortcut) } catch { errorMessage = error.localizedDescription }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayConfigurationChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.phase == .recording { self?.stop() }
                if self?.phase == .selecting { self?.cancelSelection() }
            }
        })
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
        case .recording: stop()
        case .selecting: cancelSelection()
        case .idle, .failed:
            guard recoveryMovie == nil else { showSettings(); return }
            guard ensurePermission() else { showSettings(); return }
            guard GIFExporter.bundledEncoder != nil else {
                fail("The bundled GIF encoder is missing. Build and launch Framelet.app with scripts/build-app.sh, not swift run.")
                showSettings()
                return
            }
            errorMessage = nil
            phase = .selecting
            settingsWindow?.orderOut(nil)
            selector.show()
        case .starting, .stopping, .exporting: break
        }
    }

    func cancelSelection() {
        guard phase == .selecting else { return }
        selector.close()
        phase = .idle
    }

    private func start(region: CaptureRegion, screen: NSScreen) {
        guard phase == .selecting else { return }
        phase = .starting
        let options = settings.exportOptions
        recordingOptions = options
        let recorder = ScreenRecorder()
        self.recorder = recorder
        recorder.onStopRequested = { [weak self] in self?.stop() }
        recorder.onUnexpectedStop = { [weak self, weak recorder] error in
            guard let self, let recorder, self.phase == .recording || self.phase == .starting else { return }
            self.timer?.invalidate()
            self.selector.close()
            self.phase = .stopping
            Task {
                _ = try? await recorder.stop()
                self.preserveMovieIfPresent(recorder.movieURL)
                self.recorder = nil
                self.fail(error.localizedDescription)
            }
        }
        selector.setRecording(dimOutside: settings.dimOutside)
        Task {
            do {
                try await recorder.start(region: region, screen: screen, fps: options.fps, maximumWidth: options.maximumWidth, showsCursor: settings.showsCursor)
                guard phase == .starting else { return }
                phase = .recording
                elapsed = 0
                startedAt = Date()
                let limit = settings.maximumDuration
                let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let startedAt = self.startedAt else { return }
                        self.elapsed = Date().timeIntervalSince(startedAt)
                        if self.elapsed >= Double(limit) { self.stop() }
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            } catch {
                selector.close()
                self.recorder = nil
                fail(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard phase == .recording || phase == .starting, let recorder else { return }
        phase = .stopping
        timer?.invalidate()
        timer = nil
        selector.close()
        Task {
            do {
                let movie = try await recorder.stop()
                self.recorder = nil
                recoveryMovie = movie
                UserDefaults.standard.set(movie.path, forKey: "recoveryMovie")
                retryExport()
            } catch {
                preserveMovieIfPresent(recorder.movieURL)
                self.recorder = nil
                fail(error.localizedDescription)
            }
        }
    }

    private func preserveMovieIfPresent(_ url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        recoveryMovie = url
        UserDefaults.standard.set(url.path, forKey: "recoveryMovie")
    }

    func retryExport() {
        guard phase != .exporting, let movie = recoveryMovie else { return }
        guard let encoder = GIFExporter.bundledEncoder else { fail("The bundled gifski encoder is missing."); return }
        phase = .exporting
        errorMessage = nil
        exportProgress = 0
        exportStage = "Preparing frames"
        let outputDirectory = settings.outputDirectory
        let selected = settings.exportOptions
        let options = ExportOptions(fps: recordingOptions?.fps ?? selected.fps, maximumWidth: selected.maximumWidth,
                                    quality: selected.quality, fast: selected.fast, loops: selected.loops)
        exportTask = Task {
            do {
                let url = try await GIFExporter.export(movie: movie, directory: outputDirectory, encoder: encoder, options: options) { [weak self] progress, stage in
                    await MainActor.run {
                        self?.exportProgress = progress
                        self?.exportStage = stage
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
                fail(error.localizedDescription)
                exportTask = nil
            }
        }
    }

    func cancelExport() { exportTask?.cancel() }
    func revealRecovery() { if let recoveryMovie { NSWorkspace.shared.activateFileViewerSelecting([recoveryMovie]) } }

    func discardRecovery() {
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
        if let recoveryMovie {
            let directory = recoveryMovie.deletingLastPathComponent()
            if directory.lastPathComponent.hasPrefix("Framelet-") { try? FileManager.default.removeItem(at: directory) }
        }
        recoveryMovie = nil
        recordingOptions = nil
        UserDefaults.standard.removeObject(forKey: "recoveryMovie")
    }

    private func displayConfigurationChanged() {
        if phase == .selecting { cancelSelection() }
        if phase == .recording { stop() }
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

    func beginShortcutEditing() { editingShortcut = true; shortcut.unregister() }

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
        guard [.starting, .recording, .stopping, .exporting].contains(phase) else { return true }
        let alert = NSAlert()
        alert.messageText = phase == .exporting ? "A GIF is still being exported" : "A recording is in progress"
        alert.informativeText = phase == .recording ? "Stop the recording before quitting Framelet." : "Wait for the current operation to finish, or cancel the export from the menu bar."
        alert.addButton(withTitle: "Keep Framelet Open")
        if phase == .recording { alert.addButton(withTitle: "Stop Recording") }
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn { stop() }
        return false
    }

    func shutdown() {
        shortcut.unregister()
        selector.close()
        timer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}