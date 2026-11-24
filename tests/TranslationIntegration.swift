// Run with scripts/test-translation.sh on a Mac with French/English/Spanish models installed.
import AppKit
import SwiftUI
import Translation

@main struct TranslationIntegration {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let delegate = IntegrationDelegate()
        NSApplication.shared.delegate = delegate
        withExtendedLifetime(delegate) { NSApplication.shared.run() }
    }
}

@MainActor final class IntegrationDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await verify() }
    }
    private func verify() async {
        guard let screen = NSScreen.main else { fail("No display available") }
        let visible = screen.visibleFrame
        for size in [CGSize(width: 28, height: 18), CGSize(width: 440, height: 180), CGSize(width: 200, height: 500)] {
            let selected = CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                  width: size.width, height: size.height)
            let controller = TranslationOverlayController()
            controller.show(originalText: "Bonjour, comment allez-vous aujourd’hui ?", selectionBounds: selected,
                screen: screen, targetLanguageIdentifier: "en", onTargetChange: { _ in })
            guard let window = controller.window, let container = window.contentView,
                  container.subviews.count == 2 else { fail("The toolbar and surface must share one panel") }
            container.layoutSubtreeIfNeeded()
            let surface = container.subviews[0]
            let toolbar = container.subviews[1]
            let surfaceOnScreen = window.convertToScreen(surface.convert(surface.bounds, to: nil))
            let toolbarOnScreen = window.convertToScreen(toolbar.convert(toolbar.bounds, to: nil))
            guard surfaceOnScreen == selected, visible.contains(toolbarOnScreen),
                  toolbarOnScreen.minY >= selected.maxY else { fail("Overlay changed the selection or controls overlap it") }
            guard let close = closeButton(in: toolbar), !close.isHiddenOrHasHiddenAncestor, close.isEnabled,
                  close.image?.isValid == true else { fail("The toolbar must have a visible X button") }
            let closeFrame = window.convertToScreen(close.convert(close.bounds, to: nil))
            guard toolbarOnScreen.contains(closeFrame), closeFrame.width >= 26,
                  closeFrame.height >= 26 else { fail("The language menu must leave room for the X button") }
            close.performClick(nil)
            await Task.yield()
            guard controller.window == nil, !window.isVisible else { fail("The close button must dismiss the whole overlay") }
        }
        let externalScreen = CGRect(x: -1600, y: -200, width: 1600, height: 1000)
        for selection in [CGRect(x: -1500, y: 100, width: 40, height: 20),
                          CGRect(x: -1000, y: 740, width: 300, height: 60)] {
            let layout = TranslationOverlayLayout(selection: selection, visibleFrame: externalScreen)
            guard layout.contentFrame == selection, externalScreen.contains(layout.toolbarFrame),
                  !selection.intersects(layout.toolbarFrame) else { fail("Screen edge toolbar positioning failed") }
        }
        let fullScreen = TranslationOverlayLayout(selection: externalScreen, visibleFrame: externalScreen)
        guard externalScreen.contains(fullScreen.toolbarFrame), fullScreen.toolbarInset > 0,
              fullScreen.toolbarFrame.minY > externalScreen.maxY - fullScreen.toolbarInset else {
            fail("A selection that fills the screen must leave room for the toolbar")
        }
        print("PASS: exact selection frames, screen-edge positioning, and visible, working close button")
        let availability = LanguageAvailability()
        for target in ["en", "es"] {
            guard await availability.status(from: Locale.Language(identifier: "fr"),
                                            to: Locale.Language(identifier: target)) == .installed else {
                fail("Install French, English, and Spanish translation models before running this check.")
            }
        }
        let shortcuts = ShortcutManager()
        let modifiers: UInt32 = 256 | 2048 | 4096 // Command + Option + Control
        let first = CaptureShortcut(keyCode: 100, modifiers: modifiers, key: "F8")
        let second = CaptureShortcut(keyCode: 101, modifiers: modifiers, key: "F9")
        let third = CaptureShortcut(keyCode: 109, modifiers: modifiers, key: "F10")
        guard shortcuts.registerCapture(first), shortcuts.registerFreehand(second),
              shortcuts.registerTranslation(third),
              !shortcuts.registerTranslation(first), !shortcuts.registerTranslation(second),
              !shortcuts.registerCapture(third), !shortcuts.registerFreehand(third),
              shortcuts.registerTranslation(third) else { fail("Shortcut collision protection failed") }
        print("PASS: all three shortcuts register independently and reject collisions in both directions")
        let settings = SettingsModel()
        guard !settings.translationShortcut.matches(settings.shortcut),
              !settings.translationShortcut.matches(settings.freehandShortcut) else { fail("Default translation shortcut collision") }
        let image = NSImage(size: NSSize(width: 1400, height: 160))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1400, height: 160).fill()
        ("Bonjour, comment allez-vous aujourd’hui ?" as NSString).draw(at: NSPoint(x: 30, y: 60),
            withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        image.unlockFocus()
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fail("Missing OCR fixture") }
        let result: CaptureResult
        do { result = try TextCapture.recognize(image: cgImage, singleLine: false, skipQRCodeDetection: true) }
        catch { fail("OCR failed: \(error)") }
        guard case .text(let captured) = result, captured.contains("Bonjour") else { fail("French OCR failed") }
        print("PASS: captured French text from an image: \(captured)")
        let model = TranslationOverlayModel(originalText: captured,
            targetLanguage: Locale.Language(identifier: "en"), onTargetChange: { _ in })
        let view = TranslationOverlayView(model: model, onClose: {})
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 220),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        self.window = window
        window.orderFrontRegardless()
        await waitForResult(model, containing: "Hello")
        print("PASS: production overlay automatically detected French and translated to English: \(model.translatedText)")
        model.targetLanguage = Locale.Language(identifier: "es")
        // Allow onChange to clear the old result and begin the new session.
        await Task.yield()
        await waitForResult(model, containing: "Hola")
        print("PASS: production overlay target change retranslates to Spanish: \(model.translatedText)")
        model.targetLanguage = Locale.Language(identifier: "fr")
        await Task.yield()
        await waitForResult(model, containing: "Bonjour")
        print("PASS: same-language selection returns original text")
        window.orderOut(nil)
        NSApp.terminate(nil)
    }

    private func closeButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.accessibilityLabel() == "Close translation" {
            return button
        }
        return view.subviews.lazy.compactMap { self.closeButton(in: $0) }.first
    }

    private func waitForResult(_ model: TranslationOverlayModel, containing expected: String) async {
        for _ in 0..<300 {
            if let error = model.errorMessage { fail("Translation error: \(error)") }
            if !model.isLoading && model.translatedText.contains(expected) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        fail("Timed out waiting for \(expected); last text: \(model.translatedText)")
    }
    private func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
