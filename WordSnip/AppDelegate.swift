import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsModel = SettingsModel()
    private let shortcutManager = ShortcutManager()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var overlay: SelectionOverlay?
    private var isCapturing = false
    private var isRecordingShortcut = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcutManager.onCapture = { [weak self] in
            guard let self, !self.isRecordingShortcut else { return }
            self.startCapture(mode: .rectangle)
        }
        shortcutManager.onFreehandCapture = { [weak self] in
            guard let self, !self.isRecordingShortcut else { return }
            self.startCapture(mode: .freehand)
        }
        shortcutManager.onSettings = { [weak self] in self?.showSettings() }
        settingsModel.onShortcutChange = { [weak self] shortcut in
            self?.shortcutManager.registerCapture(shortcut) ?? false
        }
        settingsModel.onFreehandShortcutChange = { [weak self] shortcut in
            self?.shortcutManager.registerFreehand(shortcut) ?? false
        }
        settingsModel.onMenuBarChange = { [weak self] visible in
            self?.configureStatusItem(visible: visible)
        }
        configureStatusItem(visible: settingsModel.showMenuBarIcon)
        let rectangleRegistered = shortcutManager.registerCapture(settingsModel.shortcut)
        let freehandRegistered = shortcutManager.registerFreehand(settingsModel.freehandShortcut)
        if !rectangleRegistered || !freehandRegistered {
            settingsModel.message = "A capture shortcut is unavailable. Choose another combination."
            showSettings()
        } else if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            showSettings()
        }
    }

    private func configureStatusItem(visible: Bool) {
        if !visible {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "Word Snip")
        item.button?.toolTip = "Word Snip"
        let menu = NSMenu()
        menu.addItem(withTitle: "Capture Rectangle", action: #selector(captureFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Capture Freehand", action: #selector(freehandFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Word Snip", action: #selector(quitFromMenu), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func captureFromMenu() { scheduleCaptureFromUI(mode: .rectangle) }
    @objc private func freehandFromMenu() { scheduleCaptureFromUI(mode: .freehand) }
    @objc private func settingsFromMenu() { showSettings() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    private func showSettings() {
        if let overlay {
            overlay.close()
            self.overlay = nil
            isCapturing = false
        }
        if settingsWindow == nil {
            let hosting = NSHostingView(rootView: SettingsView(model: settingsModel, onCapture: { [weak self] in
                self?.captureFromSettings(mode: .rectangle)
            }, onFreehandCapture: { [weak self] in
                self?.captureFromSettings(mode: .freehand)
            }, onRecordingChange: { [weak self] recording in
                self?.isRecordingShortcut = recording
            }))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: SettingsView.windowSize),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Word Snip Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.contentView = hosting
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func captureFromSettings(mode: SelectionMode) {
        isRecordingShortcut = false
        scheduleCaptureFromUI(mode: mode)
    }

    private func scheduleCaptureFromUI(mode: SelectionMode) {
        // Let the button or menu finish tracking its mouse click before opening a full-screen panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
            self?.startCapture(mode: mode)
        }
    }

    private func startCapture(mode: SelectionMode) {
        if let overlay {
            overlay.close()
            self.overlay = nil
            isCapturing = false
        }
        guard !isCapturing else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            showPermissionAlert()
            return
        }
        isCapturing = true
        settingsWindow?.orderOut(nil)
        let overlay = SelectionOverlay(mode: mode)
        overlay.onCancel = { [weak self] in
            self?.overlay = nil
            self?.isCapturing = false
        }
        overlay.onSelection = { [weak self] screen, selection in
            guard let self else { return }
            self.overlay = nil
            Task {
                // Let WindowServer remove the selection overlay before taking the screenshot.
                try? await Task.sleep(for: .milliseconds(180))
                do {
                    let text = try await TextCapture.recognize(
                        screen: screen, selection: selection, singleLine: self.settingsModel.singleLineText
                    )
                    NSPasteboard.general.clearContents()
                    guard NSPasteboard.general.setString(text, forType: .string) else {
                        throw CaptureError.clipboardUnavailable
                    }
                    self.showFeedback(on: screen)
                } catch {
                    self.showError(error.localizedDescription)
                }
                self.isCapturing = false
            }
        }
        self.overlay = overlay
        overlay.show()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording is not active for this copy"
        alert.informativeText = "Enable Screen & System Audio Recording for Word Snip, then quit and reopen the app."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit Word Snip")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could not copy text"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showFeedback(on screen: NSScreen) {
        let size = CGSize(width: 232, height: 60)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

        if let image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied") {
            let icon = NSImageView(image: image)
            icon.frame = CGRect(x: 17, y: 17, width: 26, height: 26)
            icon.contentTintColor = .systemGreen
            background.addSubview(icon)
        }

        let title = NSTextField(labelWithString: "Text copied")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white
        title.frame = CGRect(x: 54, y: 30, width: 164, height: 19)
        background.addSubview(title)

        let detail = NSTextField(labelWithString: "Ready to paste")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = NSColor.white.withAlphaComponent(0.72)
        detail.frame = CGRect(x: 54, y: 14, width: 164, height: 15)
        background.addSubview(detail)

        panel.contentView = background
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - size.width / 2,
                                   y: screen.visibleFrame.maxY - size.height - 24))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
    }
}
