import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var shortcut: CaptureShortcut
    @Published var showMenuBarIcon: Bool
    @Published var launchAtLogin: Bool
    @Published var message: String?
    @Published var isRecordingShortcut = false

    var onShortcutChange: ((CaptureShortcut) -> Bool)?
    var onMenuBarChange: ((Bool) -> Void)?

    init() {
        if let data = UserDefaults.standard.data(forKey: "captureShortcutV2"),
           let saved = try? JSONDecoder().decode(CaptureShortcut.self, from: data) {
            shortcut = saved
        } else if let legacy = UserDefaults.standard.object(forKey: "captureShortcut") as? Int,
                  let preset = CaptureShortcut.legacyPreset(legacy) {
            shortcut = preset
        } else {
            shortcut = .default
        }
        showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    func setShortcut(_ value: CaptureShortcut) -> Bool {
        guard !value.isSettingsShortcut else {
            message = "⌃⌥, is reserved for opening Settings. Choose another shortcut."
            return false
        }
        guard let data = try? JSONEncoder().encode(value) else {
            message = "Could not save the shortcut. Try again."
            return false
        }
        guard onShortcutChange?(value) == true else {
            message = "That shortcut is already in use. Try another combination."
            return false
        }
        shortcut = value
        UserDefaults.standard.set(data, forKey: "captureShortcutV2")
        UserDefaults.standard.removeObject(forKey: "captureShortcut")
        message = nil
        return true
    }

    func rejectShortcut() {
        message = "Use a key with ⌘, ⌃, or ⌥. Press Esc to cancel."
    }

    func setMenuBarIcon(_ value: Bool) {
        showMenuBarIcon = value
        UserDefaults.standard.set(value, forKey: "showMenuBarIcon")
        onMenuBarChange?(value)
    }

    func setLaunchAtLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            message = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            message = "Could not change Login Items: \(error.localizedDescription)"
        }
    }
}

struct SettingsView: View {
    static let windowSize = CGSize(width: 540, height: 600)

    @ObservedObject var model: SettingsModel
    var onCapture: () -> Void
    var onRecordingChange: (Bool) -> Void

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Word Snip")
                            .font(SettingsFont.demi(24))
                        Text("Capture text from anywhere on your Mac")
                            .font(SettingsFont.regular(13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel("CAPTURE")
                    VStack(spacing: 0) {
                        HStack(spacing: 13) {
                            settingIcon("keyboard", color: .blue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Capture shortcut").font(SettingsFont.demi(14))
                                Text("Start a selection from any app")
                                    .font(SettingsFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            ShortcutRecorder(shortcut: model.shortcut,
                                             onShortcut: { model.setShortcut($0) },
                                             onInvalid: { model.rejectShortcut() },
                                             onRecordingChange: { recording in
                                                 model.isRecordingShortcut = recording
                                                 if recording { model.message = nil }
                                                 onRecordingChange(recording)
                                             })
                                .frame(width: 160, height: 36)
                        }
                        .padding(15)

                        Divider().padding(.leading, 56)

                        HStack {
                            Text("Click the shortcut, then press your keys")
                                .font(SettingsFont.regular(11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Use default") {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                                model.setShortcut(.default)
                            }
                                .buttonStyle(.plain)
                                .font(SettingsFont.demi(11))
                                .foregroundStyle(.tint)
                                .disabled(model.shortcut == .default && model.message == nil)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                    }
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel("PREFERENCES")
                    VStack(spacing: 0) {
                        HStack(spacing: 13) {
                            settingIcon("menubar.rectangle", color: .purple)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Menu bar icon").font(SettingsFont.demi(14))
                                Text("Keep Word Snip within reach")
                                    .font(SettingsFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Menu bar icon", isOn: Binding(
                                get: { model.showMenuBarIcon },
                                set: { model.setMenuBarIcon($0) }
                            ))
                            .labelsHidden()
                        }
                        .padding(15)

                        Divider().padding(.leading, 56)

                        HStack(spacing: 13) {
                            settingIcon("arrow.up.right.square", color: .orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Launch at login").font(SettingsFont.demi(14))
                                Text("Ready when you sign in")
                                    .font(SettingsFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Launch at login", isOn: Binding(
                                get: { model.launchAtLogin },
                                set: { model.setLaunchAtLogin($0) }
                            ))
                            .labelsHidden()
                        }
                        .padding(15)
                    }
                    .cardStyle()
                }

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: model.message == nil ? "info.circle" : "exclamationmark.circle.fill")
                    Text(model.message ?? (model.isRecordingShortcut
                        ? "Press your new shortcut. Esc cancels recording."
                        : "Open Settings anytime with ⌃⌥, even if the menu bar icon is hidden."))
                }
                .font(SettingsFont.regular(11))
                .foregroundStyle(model.message == nil ? Color.secondary : Color.red)
                .frame(minHeight: 30, alignment: .topLeading)

                Spacer(minLength: 0)

                Button(action: onCapture) {
                    HStack(spacing: 11) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Capture text now")
                            .font(SettingsFont.demi(15))
                        Spacer()
                        Text(model.shortcut.title)
                            .font(SettingsFont.demi(12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .help("Start a screen selection")
            }
            .padding(.horizontal, 27)
            .padding(.bottom, 27)
            .padding(.top, 54)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(SettingsFont.demi(10))
            .tracking(1.1)
            .foregroundStyle(.secondary)
            .padding(.leading, 3)
    }

    private func settingIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum SettingsFont {
    static func regular(_ size: CGFloat) -> Font { .custom("AvenirNext-Regular", size: size) }
    static func demi(_ size: CGFloat) -> Font { .custom("AvenirNext-DemiBold", size: size) }
}

private extension View {
    func cardStyle() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: CaptureShortcut
    let onShortcut: (CaptureShortcut) -> Bool
    let onInvalid: () -> Void
    let onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let view = ShortcutRecorderControl()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Capture shortcut")
        return view
    }

    func updateNSView(_ view: ShortcutRecorderControl, context: Context) {
        view.shortcut = shortcut
        view.onShortcut = onShortcut
        view.onInvalid = onInvalid
        view.onRecordingChange = onRecordingChange
        view.setAccessibilityValue(shortcut.title)
    }
}

private final class ShortcutRecorderControl: NSView {
    var shortcut: CaptureShortcut = .default { didSet { needsDisplay = true } }
    var onShortcut: ((CaptureShortcut) -> Bool)?
    var onInvalid: (() -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var isRecording = false { didSet { needsDisplay = true; onRecordingChange?(isRecording) } }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        NSColor.controlAccentColor.withAlphaComponent(isRecording ? 0.16 : 0.08).setFill()
        outline.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        outline.lineWidth = isRecording ? 1.5 : 1
        outline.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let label = NSAttributedString(string: isRecording ? "Press keys…" : shortcut.title, attributes: [
            .font: NSFont(name: "AvenirNext-DemiBold", size: 13) ?? NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        label.draw(in: CGRect(x: 8, y: (bounds.height - 18) / 2, width: bounds.width - 16, height: 18))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if window?.makeFirstResponder(self) == true { beginRecording() }
    }

    override func keyDown(with event: NSEvent) {
        if isRecording { record(event) }
        else { super.keyDown(with: event) }
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let window {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.stopRecording() }
        } else {
            stopRecording()
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording, self.window?.isKeyWindow == true else { return event }
            self.record(event)
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        isRecording = false
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == 53 {
            stopRecording()
            window?.makeFirstResponder(nil)
            return
        }
        guard let shortcut = CaptureShortcut(event: event) else {
            onInvalid?()
            NSSound.beep()
            return
        }
        guard onShortcut?(shortcut) == true else {
            NSSound.beep()
            return
        }
        stopRecording()
        window?.makeFirstResponder(nil)
    }
}
