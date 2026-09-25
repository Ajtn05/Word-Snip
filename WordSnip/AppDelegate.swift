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

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcutManager.onCapture = { [weak self] in self?.startCapture() }
        shortcutManager.onSettings = { [weak self] in self?.showSettings() }
        settingsModel.onShortcutChange = { [weak self] shortcut in
            self?.shortcutManager.registerCapture(shortcut) ?? false
        }
        settingsModel.onMenuBarChange = { [weak self] visible in
            self?.configureStatusItem(visible: visible)
        }
        configureStatusItem(visible: settingsModel.showMenuBarIcon)
        if !shortcutManager.registerCapture(settingsModel.shortcut) {
            settingsModel.message = "The chosen capture shortcut is unavailable. Choose another."
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
        menu.addItem(withTitle: "Capture Text", action: #selector(captureFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Word Snip", action: #selector(quitFromMenu), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func captureFromMenu() { startCapture() }
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
                self?.settingsWindow?.orderOut(nil)
                self?.startCapture()
            }))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 340),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Word Snip Settings"
            window.contentView = hosting
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func startCapture() {
        guard !isCapturing else { return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            showPermissionAlert()
            return
        }
        isCapturing = true
        settingsWindow?.orderOut(nil)
        let overlay = SelectionOverlay()
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
                    let text = try await TextCapture.recognize(screen: screen, selection: selection)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    self.showFeedback("Copied text to clipboard")
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
        alert.informativeText = "After enabling access, quit Word Snip completely and reopen it. If access already appears enabled, check that it is enabled for the copy you launched:\n\n\(Bundle.main.bundleURL.path)"
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

    private func showFeedback(_ message: String) {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 250, height: 38),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        panel.contentView?.layer?.cornerRadius = 10
        label.frame = CGRect(x: 8, y: 7, width: 234, height: 24)
        panel.contentView?.addSubview(label)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        if let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - 125, y: screen.visibleFrame.maxY - 70))
        }
        panel.orderFrontRegardless()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            panel.orderOut(nil)
        }
    }
}
