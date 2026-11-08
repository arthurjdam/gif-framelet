import SwiftUI
import ServiceManagement

/// Open-at-login state backed by `SMAppService.mainApp`. Only usable from a real .app bundle, not `swift run`.
@MainActor
final class LoginItem: ObservableObject {
    static let isAvailable = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    @Published private(set) var status = SMAppService.Status.notRegistered
    @Published private(set) var errorMessage: String?

    var isOn: Bool { status == .enabled || status == .requiresApproval }

    func refresh() { if Self.isAvailable { status = SMAppService.mainApp.status } }

    func set(_ enabled: Bool) {
        guard Self.isAvailable, enabled != isOn else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(enabled ? "add Framelet to" : "remove Framelet from") Login Items. \(error.localizedDescription)"
        }
        refresh()
    }
}

struct GeneralSettings: View {
    @StateObject private var loginItem = LoginItem()

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open at login", isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) }))
                    .disabled(!LoginItem.isAvailable)
                if !LoginItem.isAvailable {
                    Text("Available when Framelet runs from its app bundle.").foregroundStyle(.secondary)
                } else if loginItem.status == .requiresApproval {
                    Label("Allow Framelet in System Settings > General > Login Items.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Open Login Items Settings", systemImage: "arrow.up.forward.app") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let message = loginItem.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            Section("About") {
                LabeledContent("Version", value: AboutPanel.version ?? "Development build")
                Button("About Framelet", systemImage: "info.circle") { AboutPanel.show() }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }
}

@MainActor
enum AboutPanel {
    static var shortVersion: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
    static var build: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String }
    static var version: String? { shortVersion.map { v in build.map { "\(v) (\($0))" } ?? v } }

    static var noticeURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ThirdParty/NOTICE.md")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
        ]
        let text = NSMutableAttributedString(string: "GIF encoding by ", attributes: base)
        var gifski = base
        gifski[.link] = URL(string: "https://gif.ski")
        text.append(NSAttributedString(string: "gifski" + (GIFExporter.encoderVersion.map { " \($0)" } ?? ""), attributes: gifski))
        if let noticeURL {
            var notice = base
            notice[.link] = noticeURL
            text.append(NSAttributedString(string: "\n", attributes: base))
            text.append(NSAttributedString(string: "Third-party notices", attributes: notice))
        }
        return text
    }

    static func show() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.applicationName: "Framelet", .credits: credits]
        options[.applicationVersion] = shortVersion ?? "Development build"
        options[.version] = build ?? ""
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}
