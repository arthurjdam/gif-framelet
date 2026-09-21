import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            Tab("Recording", systemImage: "viewfinder") {
                Form {
                    Section("Screen Recording") {
                        LabeledContent("Permission") {
                            Label(controller.hasPermission ? "Allowed" : "Not allowed", systemImage: controller.hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(controller.hasPermission ? Color.green : Color.orange)
                        }
                        if !controller.hasPermission {
                            Button("Request Access", systemImage: "lock.open") { controller.ensurePermission() }
                            Button("Open System Settings", systemImage: "arrow.up.forward.app") { controller.openPrivacySettings() }
                        }
                    }
                    Section("Capture") {
                        Toggle("Include pointer", isOn: $settings.showsCursor)
                        Toggle("Dim outside region while recording", isOn: $settings.dimOutside)
                        Picker("Stop automatically after", selection: $settings.maximumDuration) {
                            Text("15 seconds").tag(15)
                            Text("30 seconds").tag(30)
                            Text("1 minute").tag(60)
                            Text("2 minutes").tag(120)
                        }
                    }.disabled(controller.isBusy)
                    Section("Keyboard Shortcut") {
                        LabeledContent("Select region / stop recording") {
                            ShortcutRecorder(controller: controller, shortcut: settings.shortcut)
                                .frame(width: 150, height: 28)
                        }
                        Button("Restore Default", systemImage: "arrow.counterclockwise") {
                            controller.endShortcutEditing(.defaultShortcut)
                        }
                    }.disabled(controller.isBusy)
                }.formStyle(.grouped)
            }
            Tab("GIF", systemImage: "photo.stack") {
                Form {
                    Section("Export") {
                        Picker("Frame rate", selection: $settings.fps) {
                            ForEach([5, 10, 15, 20, 25, 30], id: \.self) { Text("\($0) fps").tag($0) }
                        }
                        Picker("Maximum width", selection: $settings.maximumWidth) {
                            ForEach([320, 480, 640, 800, 1024, 1280, 1920, 2560], id: \.self) { Text("\($0) px").tag($0) }
                        }
                        LabeledContent("Quality", value: "\(Int(settings.quality))%")
                        Slider(value: $settings.quality, in: 20...100, step: 1) {
                            Text("GIF quality")
                        } minimumValueLabel: {
                            Image(systemName: "doc.zipper").help("Smaller file")
                        } maximumValueLabel: {
                            Image(systemName: "sparkles").help("Higher quality")
                        }
                        Toggle("Faster encoding", isOn: $settings.fast)
                            .help("Uses less encoding effort; files may be larger and slightly lower quality.")
                        Toggle("Loop forever", isOn: $settings.loops)
                    }.disabled(controller.isBusy)
                    Section("Encoder") {
                        LabeledContent("gifski", value: GIFExporter.bundledEncoder == nil ? "Not bundled" : "1.34.0")
                        Link("Encoder & Licensing", destination: URL(string: "https://gif.ski")!)
                    }
                }.formStyle(.grouped)
            }
            Tab("Files", systemImage: "folder") {
                Form {
                    Section("Destination") {
                        LabeledContent("Save GIFs to") {
                            Text(settings.outputDirectory.path(percentEncoded: false))
                                .lineLimit(1).truncationMode(.middle)
                                .help(settings.outputDirectory.path)
                        }
                        Button("Choose Folder...", systemImage: "folder.badge.plus") { controller.chooseDirectory() }
                            .disabled(controller.phase == .exporting)
                        Toggle("Reveal GIF in Finder after export", isOn: $settings.revealAfterExport)
                    }
                    Section("Activity") {
                        LabeledContent("Status", value: controller.statusText)
                        if controller.phase == .exporting {
                            if controller.exportStage == "Preparing frames" {
                                ProgressView(value: controller.exportProgress)
                            } else { ProgressView().controlSize(.small) }
                            Button("Cancel Export", systemImage: "xmark") { controller.cancelExport() }
                        }
                        if let message = controller.errorMessage {
                            Button("Show Error...", systemImage: "exclamationmark.triangle") { controller.showError(message) }
                        }
                        if controller.recoveryMovie != nil && controller.phase != .exporting {
                            Button("Retry Export", systemImage: "arrow.clockwise") { controller.retryExport() }
                            Button("Reveal Original Recording", systemImage: "film") { controller.revealRecovery() }
                        }
                    }
                }.formStyle(.grouped)
            }
        }
        .padding(12)
        .frame(width: 520, height: 540)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let controller: AppController
    let shortcut: Shortcut

    func makeNSView(context: Context) -> ShortcutButton {
        let button = ShortcutButton()
        button.onBegin = { controller.beginShortcutEditing() }
        button.onEnd = { controller.endShortcutEditing($0) }
        button.bezelStyle = .rounded
        button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        button.toolTip = "Record a shortcut with Command, Option, or Control. Escape cancels."
        button.setAccessibilityLabel("Recording keyboard shortcut")
        return button
    }

    func updateNSView(_ button: ShortcutButton, context: Context) {
        button.shortcutTitle = shortcut.display
        if !button.recording { button.title = shortcut.display }
        button.isEnabled = !controller.isBusy
    }

    static func dismantleNSView(_ button: ShortcutButton, coordinator: ()) { button.finish(nil) }
}

private final class ShortcutButton: NSButton {
    var onBegin: (() -> Void)?
    var onEnd: ((Shortcut?) -> Void)?
    var shortcutTitle = ""
    private(set) var recording = false
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let window else { finish(nil); return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !recording else { return }
        recording = true
        title = "Press shortcut..."
        window?.makeFirstResponder(self)
        onBegin?()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Int(event.keyCode) == kVK_Escape { self.finish(nil); return nil }
            guard let shortcut = Shortcut(event: event) else { NSSound.beep(); return nil }
            self.finish(shortcut)
            return nil
        }
    }

    override func resignFirstResponder() -> Bool {
        finish(nil)
        return super.resignFirstResponder()
    }

    func finish(_ shortcut: Shortcut?) {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        title = shortcut?.display ?? shortcutTitle
        onEnd?(shortcut)
    }
}