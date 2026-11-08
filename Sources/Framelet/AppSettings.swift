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
    @Published private(set) var outputStatus = FolderStatus.ok
    @Published private(set) var shortcut: Shortcut

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "fps": 15, "maximumWidth": 1280, "quality": 80.0, "fast": false,
            "loops": true, "showsCursor": true, "dimOutside": true,
            "maximumDuration": 60, "revealAfterExport": true
        ])
        fps = defaults.integer(forKey: "fps")
        maximumWidth = defaults.integer(forKey: "maximumWidth")
        quality = defaults.double(forKey: "quality")
        fast = defaults.bool(forKey: "fast")
        loops = defaults.bool(forKey: "loops")
        showsCursor = defaults.bool(forKey: "showsCursor")
        dimOutside = defaults.bool(forKey: "dimOutside")
        maximumDuration = min(max(defaults.integer(forKey: "maximumDuration"), 15), 120)
        revealAfterExport = defaults.bool(forKey: "revealAfterExport")
        let bookmark = defaults.data(forKey: "outputBookmark")
        var stale = false
        if let bookmark, let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale) {
            outputDirectory = url
        } else if let path = defaults.string(forKey: "outputPath")
                    ?? bookmark.flatMap({ URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: $0)?.path }) {
            outputDirectory = URL(fileURLWithPath: path, isDirectory: true) // Keep the chosen folder so validation can report it.
        } else {
            outputDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        }
        shortcut = defaults.data(forKey: "shortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .defaultShortcut
        if stale { try? setDirectory(outputDirectory) }
        refreshOutputStatus()
    }

    var exportOptions: ExportOptions {
        ExportOptions(fps: fps, maximumWidth: maximumWidth, quality: Int(quality), fast: fast, loops: loops)
    }

    func setDirectory(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: "outputBookmark")
        defaults.set(url.path(percentEncoded: false), forKey: "outputPath")
        outputDirectory = url
        refreshOutputStatus()
    }

    func refreshOutputStatus() { outputStatus = FolderStatus(of: outputDirectory) }

    /// A readable explanation when GIFs can't be saved to the output folder, or nil when it is usable.
    var outputProblem: String? {
        let path = outputDirectory.path(percentEncoded: false)
        switch outputStatus {
        case .ok: return nil
        case .missing: return "The output folder \"\(path)\" is missing, or its disk is not connected. Reconnect it or choose another folder, then retry the export."
        case .notDirectory: return "The output location \"\(path)\" is a file, not a folder. Choose another folder, then retry the export."
        case .notWritable: return "Framelet can't write to the output folder \"\(path)\". Choose another folder, then retry the export."
        }
    }

    func setShortcut(_ value: Shortcut) {
        shortcut = value
        defaults.set(try? JSONEncoder().encode(value), forKey: "shortcut")
    }
}

enum FolderStatus: Equatable {
    case ok, missing, notDirectory, notWritable

    init(of url: URL) {
        var isDirectory: ObjCBool = false
        let path = url.path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) { self = .missing }
        else if !isDirectory.boolValue { self = .notDirectory }
        else { self = FileManager.default.isWritableFile(atPath: path) ? .ok : .notWritable }
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
}

extension Shortcut {
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
        switch Int(event.keyCode) {
        case kVK_Space: key = "Space"
        case kVK_Return: key = "Return"
        case kVK_Tab: key = "Tab"
        case kVK_LeftArrow: key = "\u{2190}"
        case kVK_RightArrow: key = "\u{2192}"
        case kVK_DownArrow: key = "\u{2193}"
        case kVK_UpArrow: key = "\u{2191}"
        default: key = text.uppercased()
        }
    }
}