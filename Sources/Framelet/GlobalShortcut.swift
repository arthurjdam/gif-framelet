import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().onPress?()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: Shortcut) throws {
        unregister()
        let identifier = EventHotKeyID(signature: 0x46524D4C, id: 1)
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        guard result == noErr else {
            throw RecorderError.message("This shortcut is unavailable or used by another app. Choose a different combination. (\(result))")
        }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}