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

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
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
            } else if controller.phase == .exporting {
                Image(systemName: "ellipsis")
            }
        }
        .accessibilityLabel(controller.phase == .recording ? "Framelet recording, \(controller.elapsedText)" : "Framelet")
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
                .disabled(controller.recoveryMovie != nil)
        case .selecting:
            Button("Cancel Selection", systemImage: "xmark") { controller.cancelSelection() }
        case .recording:
            Button("Stop Recording  \(controller.settings.shortcut.display)", systemImage: "stop.fill") { controller.stop() }
        case .starting, .stopping:
            Text(controller.phase == .starting ? "Starting capture..." : "Finishing capture...")
        case .exporting:
            Button("Cancel Export", systemImage: "xmark") { controller.cancelExport() }
        }
        if let message = controller.errorMessage {
            Button("Show Error...", systemImage: "exclamationmark.triangle") { controller.showError(message) }
        }
        if controller.recoveryMovie != nil && controller.phase != .exporting {
            Button("Retry GIF Export", systemImage: "arrow.clockwise") { controller.retryExport() }
            Button("Reveal Original Recording", systemImage: "film") { controller.revealRecovery() }
            Button("Discard Recording...", systemImage: "trash", role: .destructive) { controller.discardRecovery() }
        }
        if let lastExport = controller.lastExport {
            Divider()
            Button("Show Last GIF in Finder", systemImage: "doc.richtext") {
                NSWorkspace.shared.activateFileViewerSelecting([lastExport])
            }
            Button("Copy GIF", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([lastExport as NSURL])
            }
        }
        Divider()
        Button("Open Output Folder", systemImage: "folder") { NSWorkspace.shared.open(controller.settings.outputDirectory) }
        Button("Settings...", systemImage: "gearshape") { controller.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Framelet") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}