import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var discardHotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    var onDiscard: (() -> Void)?

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            MainActor.assumeIsolated {
                let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                (identifier.id == 2 ? shortcut.onDiscard : shortcut.onPress)?()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: Shortcut) throws {
        unregister()
        hotKey = try Self.install(shortcut, id: 1)
    }

    /// The shortcut plus Option discards a recording; registered only while one is in progress.
    func registerDiscard(_ shortcut: Shortcut) throws {
        unregisterDiscard()
        discardHotKey = try Self.install(shortcut.discardVariant, id: 2)
    }

    private static func install(_ shortcut: Shortcut, id: UInt32) throws -> EventHotKeyRef? {
        var hotKey: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x46524D4C, id: id)
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        guard result == noErr else {
            throw RecorderError.message("This shortcut is unavailable or used by another app. Choose a different combination. (\(result))")
        }
        return hotKey
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    func unregisterDiscard() {
        if let discardHotKey { UnregisterEventHotKey(discardHotKey) }
        discardHotKey = nil
    }
}

extension Shortcut {
    var discardVariant: Shortcut { Shortcut(keyCode: keyCode, modifiers: modifiers | UInt32(optionKey), key: key) }
}
