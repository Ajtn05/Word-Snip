import AppKit
import Carbon.HIToolbox

struct CaptureShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    static let `default` = CaptureShortcut(keyCode: UInt32(kVK_ANSI_2),
                                           modifiers: UInt32(controlKey | shiftKey), key: "2")
    static let defaultFreehand = CaptureShortcut(keyCode: UInt32(kVK_ANSI_3),
                                                modifiers: UInt32(controlKey | shiftKey), key: "3")
    static let alternateFreehand = CaptureShortcut(keyCode: UInt32(kVK_ANSI_4),
                                                  modifiers: UInt32(controlKey | shiftKey), key: "4")

    static func legacyPreset(_ value: Int) -> CaptureShortcut? {
        switch value {
        case 0: .default
        case 1: CaptureShortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(controlKey | shiftKey), key: "3")
        case 2: CaptureShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey), key: "S")
        case 3: CaptureShortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), key: "2")
        default: nil
        }
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0,
              let key = Self.keyLabel(for: event) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
    }

    var title: String {
        var title = ""
        if modifiers & UInt32(controlKey) != 0 { title += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { title += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { title += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { title += "⌘" }
        return title + key
    }

    var isSettingsShortcut: Bool {
        keyCode == UInt32(kVK_ANSI_Comma) && modifiers == UInt32(controlKey | optionKey)
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            guard let characters = event.charactersIgnoringModifiers,
                  characters.unicodeScalars.count == 1,
                  let scalar = characters.unicodeScalars.first,
                  !CharacterSet.controlCharacters.contains(scalar),
                  !CharacterSet.whitespacesAndNewlines.contains(scalar) else { return nil }
            return characters.uppercased()
        }
    }
}

final class ShortcutManager {
    var onCapture: (() -> Void)?
    var onFreehandCapture: (() -> Void)?
    var onSettings: (() -> Void)?
    private var captureHotKey: EventHotKeyRef?
    private var currentShortcut: CaptureShortcut?
    private var freehandHotKey: EventHotKeyRef?
    private var currentFreehandShortcut: CaptureShortcut?
    private var settingsHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard result == noErr else { return result }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            switch hotKeyID.id {
            case 1: manager.onCapture?()
            case 2: manager.onSettings?()
            case 3: manager.onFreehandCapture?()
            default: break
            }
            return noErr
        }, 1, &eventType, context, &eventHandler)

        // Settings stays reachable even when the menu bar icon is hidden.
        let settingsID = EventHotKeyID(signature: fourCharCode("WSNP"), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_Comma), UInt32(controlKey | optionKey), settingsID, GetApplicationEventTarget(), 0, &settingsHotKey)
    }

    deinit {
        if let captureHotKey { UnregisterEventHotKey(captureHotKey) }
        if let freehandHotKey { UnregisterEventHotKey(freehandHotKey) }
        if let settingsHotKey { UnregisterEventHotKey(settingsHotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    @discardableResult
    func registerCapture(_ shortcut: CaptureShortcut) -> Bool {
        guard !shortcut.isSettingsShortcut, shortcut != currentFreehandShortcut else { return false }
        if shortcut == currentShortcut, captureHotKey != nil { return true }
        let previous = currentShortcut
        if let captureHotKey { UnregisterEventHotKey(captureHotKey) }
        captureHotKey = nil
        if installCapture(shortcut) {
            currentShortcut = shortcut
            return true
        }
        if let previous, installCapture(previous) { currentShortcut = previous }
        else { currentShortcut = nil }
        return false
    }

    private func installCapture(_ shortcut: CaptureShortcut) -> Bool {
        let id = EventHotKeyID(signature: fourCharCode("WSNP"), id: 1)
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &captureHotKey) == noErr
    }

    @discardableResult
    func registerFreehand(_ shortcut: CaptureShortcut) -> Bool {
        guard !shortcut.isSettingsShortcut, shortcut != currentShortcut else { return false }
        if shortcut == currentFreehandShortcut, freehandHotKey != nil { return true }
        let previous = currentFreehandShortcut
        if let freehandHotKey { UnregisterEventHotKey(freehandHotKey) }
        freehandHotKey = nil
        if installFreehand(shortcut) {
            currentFreehandShortcut = shortcut
            return true
        }
        if let previous, installFreehand(previous) { currentFreehandShortcut = previous }
        else { currentFreehandShortcut = nil }
        return false
    }

    private func installFreehand(_ shortcut: CaptureShortcut) -> Bool {
        let id = EventHotKeyID(signature: fourCharCode("WSNP"), id: 3)
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &freehandHotKey) == noErr
    }

    private func fourCharCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
