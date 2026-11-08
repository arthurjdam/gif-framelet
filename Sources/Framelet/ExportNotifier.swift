import AppKit
import UserNotifications
import RecorderCore

/// Posts export results to Notification Center. Authorization is requested on the first post; if it's denied, posting does nothing.
@MainActor
final class ExportNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let successCategory = "export.success", failureCategory = "export.failure"
    private static let copyAction = "copy", revealAction = "reveal"
    var onShowError: (() -> Void)?

    /// Nil outside a bundled .app (swift run), where UNUserNotificationCenter.current() traps.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
    }

    /// Call at launch so action responses are handled, including ones that relaunch the app. Doesn't ask for permission.
    func activate() {
        guard let center else { return }
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.successCategory, actions: [
                UNNotificationAction(identifier: Self.copyAction, title: "Copy"),
                UNNotificationAction(identifier: Self.revealAction, title: "Show in Finder")
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.failureCategory, actions: [], intentIdentifiers: [])
        ])
    }

    func exported(_ url: URL, summary: GIFSummary?) {
        center?.removeDeliveredNotifications(withIdentifiers: [Self.failureCategory])
        post(id: UUID().uuidString, category: Self.successCategory, title: "GIF saved" + (summary.map { " \u{2014} \($0.text())" } ?? ""),
             body: url.lastPathComponent, path: url.path)
    }

    func failed(_ message: String) {
        post(id: Self.failureCategory, category: Self.failureCategory, title: "GIF export failed",
             body: message + " Open the Framelet menu to retry.", path: nil)
    }

    private func post(id: String, category: String, title: String, body: String, path: String?) {
        guard let center else { return }
        Task {
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.categoryIdentifier = category
            if let path { content.userInfo = ["path": path] }
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let path = response.notification.request.content.userInfo["path"] as? String
        await MainActor.run {
            guard let path else {
                if action == UNNotificationDefaultActionIdentifier { onShowError?() }
                return
            }
            let url = URL(fileURLWithPath: path)
            switch action {
            case Self.copyAction: AppController.copy(url)
            case Self.revealAction, UNNotificationDefaultActionIdentifier: NSWorkspace.shared.activateFileViewerSelecting([url])
            default: break
            }
        }
    }
}
