import SwiftUI

struct FrameletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            RecorderMenu(controller: delegate.controller)
        } label: {
            MenuBarLabel(controller: delegate.controller)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        controller.activateNotifications()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.launch()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller.refreshPermission()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.canQuit() ? .terminateNow : .terminateCancel
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var controller: AppController

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: controller.phase == .recording ? "stop.circle.fill" : "viewfinder")
                .symbolRenderingMode(.palette)
                .foregroundStyle(controller.phase == .recording ? Color.red : Color.primary)
            if controller.phase == .recording {
                Text(controller.elapsedText).monospacedDigit()
            } else if controller.phase == .countingDown {
                Text("\(controller.countdownRemaining)").monospacedDigit()
            } else if controller.phase == .exporting {
                Image(systemName: "ellipsis")
            }
        }
        .accessibilityLabel(controller.phase == .recording ? "Framelet recording, \(controller.elapsedText)"
                            : controller.phase == .countingDown ? "Framelet recording in \(controller.countdownRemaining)" : "Framelet")
    }
}

private struct RecorderMenu: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Text("Framelet").font(.headline)
        Text(controller.statusText)
        Divider()
        switch controller.phase {
        case .idle, .failed:
            Button("Record Region...  \(controller.settings.shortcut.display)", systemImage: "viewfinder") { controller.trigger() }
            Button("Record Last Region", systemImage: "arrow.counterclockwise") { controller.recordLastRegion() }
                .disabled(controller.lastRegion == nil)
        case .selecting:
            Button("Cancel Selection", systemImage: "xmark") { controller.cancelSelection() }
        case .countingDown:
            Button("Cancel Countdown  \(controller.settings.shortcut.display)", systemImage: "xmark") { controller.cancelCountdown() }
        case .recording:
            Button("Stop Recording  \(controller.settings.shortcut.display)", systemImage: "stop.fill") { controller.stop() }
            Button("Discard Recording" + (controller.settings.shortcut.discardVariant.map { "  \($0.display)" } ?? ""), systemImage: "trash", role: .destructive) { controller.discard() }
        case .starting:
            Button("Cancel", systemImage: "xmark") { controller.stop() }
        case .stopping:
            Text("Finishing capture...")
        case .previewing:
            Button("Show Preview", systemImage: "play.rectangle") { controller.trigger() }
        case .exporting:
            Button("Cancel Export", systemImage: "xmark") { controller.cancelExport() }
        }
        if let message = controller.errorMessage {
            Button("Show Error...", systemImage: "exclamationmark.triangle") { controller.showError(message) }
        }
        if controller.recoveryMovie != nil && !controller.isBusy {
            Button("Retry GIF Export", systemImage: "arrow.clockwise") { controller.retryExport() }
            Button("Reveal Original Recording", systemImage: "film") { controller.revealRecovery() }
            Button("Discard Recording...", systemImage: "trash", role: .destructive) { controller.discardRecovery() }
        }
        if let lastExport = controller.lastExport {
            Divider()
            Button("Show Last GIF in Finder" + (controller.lastExportSize.map { " (\($0))" } ?? ""), systemImage: "doc.richtext") {
                NSWorkspace.shared.activateFileViewerSelecting([lastExport])
            }
            Button("Copy GIF", systemImage: "doc.on.doc") { AppController.copy(lastExport) }
        }
        Divider()
        Button("Open Output Folder", systemImage: "folder") { NSWorkspace.shared.open(controller.settings.outputDirectory) }
        Button("Settings...", systemImage: "gearshape") { controller.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("About Framelet") { AboutPanel.show() }
        Button("Quit Framelet") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}