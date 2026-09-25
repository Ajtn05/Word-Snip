import AppKit
import Carbon.HIToolbox

enum CaptureShortcut: Int, CaseIterable, Identifiable {
    case controlShift2 = 0
    case controlShift3
    case controlOptionS
    case commandShift2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .controlShift2: "⌃⇧2"
        case .controlShift3: "⌃⇧3"
        case .controlOptionS: "⌃⌥S"
        case .commandShift2: "⌘⇧2"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .controlShift2, .commandShift2: UInt32(kVK_ANSI_2)
        case .controlShift3: UInt32(kVK_ANSI_3)
        case .controlOptionS: UInt32(kVK_ANSI_S)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .controlShift2, .controlShift3: UInt32(controlKey | shiftKey)
        case .controlOptionS: UInt32(controlKey | optionKey)
        case .commandShift2: UInt32(cmdKey | shiftKey)
        }
    }
}

final class ShortcutManager {
    var onCapture: (() -> Void)?
    var onSettings: (() -> Void)?
    private var captureHotKey: EventHotKeyRef?
    private var currentShortcut: CaptureShortcut?
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
        if let settingsHotKey { UnregisterEventHotKey(settingsHotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    @discardableResult
    func registerCapture(_ shortcut: CaptureShortcut) -> Bool {
        let previous = currentShortcut
        if let captureHotKey { UnregisterEventHotKey(captureHotKey) }
        captureHotKey = nil
        if installCapture(shortcut) {
            currentShortcut = shortcut
            return true
        }
        if let previous { _ = installCapture(previous) }
        return false
    }

    private func installCapture(_ shortcut: CaptureShortcut) -> Bool {
        let id = EventHotKeyID(signature: fourCharCode("WSNP"), id: 1)
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &captureHotKey) == noErr
    }

    private func fourCharCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
