import SwiftUI
import Carbon.HIToolbox
import RecorderCore

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var fps: Int { didSet { defaults.set(fps, forKey: "fps") } }
    @Published var maximumWidth: Int { didSet { defaults.set(maximumWidth, forKey: "maximumWidth") } }
    @Published var quality: Double { didSet { defaults.set(quality, forKey: "quality") } }
    @Published var fast: Bool { didSet { defaults.set(fast, forKey: "fast") } }
    @Published var loops: Bool { didSet { defaults.set(loops, forKey: "loops") } }
    @Published var showsCursor: Bool { didSet { defaults.set(showsCursor, forKey: "showsCursor") } }
    @Published var dimOutside: Bool { didSet { defaults.set(dimOutside, forKey: "dimOutside") } }
    @Published var maximumDuration: Int { didSet { defaults.set(maximumDuration, forKey: "maximumDuration") } }
    @Published var revealAfterExport: Bool { didSet { defaults.set(revealAfterExport, forKey: "revealAfterExport") } }
    @Published private(set) var outputDirectory: URL
    @Published private(set) var shortcut: Shortcut

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "fps": 15, "maximumWidth": 1280, "quality": 80.0, "fast": false,
            "loops": true, "showsCursor": true, "dimOutside": true,
            "maximumDuration": 60, "revealAfterExport": true
        ])
        fps = min(max(defaults.integer(forKey: "fps"), 5), 30)
        maximumWidth = min(max(defaults.integer(forKey: "maximumWidth"), 320), 2560)
        quality = min(max(defaults.double(forKey: "quality"), 20), 100)
        fast = defaults.bool(forKey: "fast")
        loops = defaults.bool(forKey: "loops")
        showsCursor = defaults.bool(forKey: "showsCursor")
        dimOutside = defaults.bool(forKey: "dimOutside")
        maximumDuration = min(max(defaults.integer(forKey: "maximumDuration"), 15), 120)
        revealAfterExport = defaults.bool(forKey: "revealAfterExport")
        if let data = defaults.data(forKey: "outputBookmark") {
            var stale = false
            outputDirectory = (try? URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale))
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        } else {
            outputDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        }
        if let data = defaults.data(forKey: "shortcut"), let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .defaultShortcut
        }
    }

    var exportOptions: ExportOptions {
        ExportOptions(fps: fps, maximumWidth: maximumWidth, quality: Int(quality), fast: fast, loops: loops)
    }

    func setDirectory(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: "outputBookmark")
        outputDirectory = url
    }

    func setShortcut(_ value: Shortcut) {
        shortcut = value
        defaults.set(try? JSONEncoder().encode(value), forKey: "shortcut")
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    static let defaultShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_8), modifiers: UInt32(cmdKey | shiftKey), key: "8")

    var display: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "\u{2303}" }
        if modifiers & UInt32(optionKey) != 0 { result += "\u{2325}" }
        if modifiers & UInt32(shiftKey) != 0 { result += "\u{21e7}" }
        if modifiers & UInt32(cmdKey) != 0 { result += "\u{2318}" }
        return result + key
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty,
              let text = event.characters(byApplyingModifiers: []), !text.isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        switch event.keyCode {
        case 49: key = "Space"
        case 36: key = "Return"
        case 48: key = "Tab"
        case 123: key = "\u{2190}"
        case 124: key = "\u{2192}"
        case 125: key = "\u{2193}"
        case 126: key = "\u{2191}"
        default: key = text.uppercased()
        }
    }
}