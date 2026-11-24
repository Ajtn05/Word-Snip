import AppKit
import ServiceManagement
import SwiftUI
#if canImport(Translation)
import Translation
#endif

@MainActor
final class SettingsModel: ObservableObject {
    @Published var shortcut: CaptureShortcut
    @Published var freehandShortcut: CaptureShortcut
    @Published var showMenuBarIcon: Bool
    @Published var singleLineText: Bool
    @Published private(set) var collapseOCRSpaces: Bool
    @Published private(set) var recognitionLanguage: String?
    @Published var translateSelectedText: Bool
    @Published var translationTargetLanguage: String
    @Published var launchAtLogin: Bool
    @Published var message: String?
    @Published var isRecordingShortcut = false

    var onShortcutChange: ((CaptureShortcut) -> Bool)?
    var onFreehandShortcutChange: ((CaptureShortcut) -> Bool)?
    var onMenuBarChange: ((Bool) -> Void)?

    init() {
        let initialShortcut: CaptureShortcut
        if let data = UserDefaults.standard.data(forKey: "captureShortcutV2"),
           let saved = try? JSONDecoder().decode(CaptureShortcut.self, from: data) {
            initialShortcut = saved
        } else if let legacy = UserDefaults.standard.object(forKey: "captureShortcut") as? Int,
                  let preset = CaptureShortcut.legacyPreset(legacy) {
            initialShortcut = preset
        } else {
            initialShortcut = .default
        }
        shortcut = initialShortcut
        if let data = UserDefaults.standard.data(forKey: "freehandShortcut"),
           let saved = try? JSONDecoder().decode(CaptureShortcut.self, from: data) {
            freehandShortcut = saved
        } else {
            freehandShortcut = initialShortcut == .defaultFreehand ? .alternateFreehand : .defaultFreehand
        }
        showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        singleLineText = UserDefaults.standard.bool(forKey: "singleLineText")
        collapseOCRSpaces = UserDefaults.standard.bool(forKey: "collapseOCRSpaces")
        if #available(macOS 15.0, *) {
            translateSelectedText = UserDefaults.standard.bool(forKey: "translateSelectedText")
            if let saved = UserDefaults.standard.string(forKey: "translationTargetLanguage"), !saved.isEmpty {
                translationTargetLanguage = saved
            } else {
                translationTargetLanguage = "en"
            }
        } else {
            translateSelectedText = false
            translationTargetLanguage = "en"
            UserDefaults.standard.removeObject(forKey: "translateSelectedText")
        }
        if let savedLanguage = UserDefaults.standard.string(forKey: "recognitionLanguage"),
           TextCapture.supportedRecognitionLanguages.contains(savedLanguage) {
            recognitionLanguage = savedLanguage
        }
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

    @discardableResult
    func setFreehandShortcut(_ value: CaptureShortcut) -> Bool {
        guard !value.isSettingsShortcut else {
            message = "⌃⌥, is reserved for opening Settings. Choose another shortcut."
            return false
        }
        guard let data = try? JSONEncoder().encode(value) else {
            message = "Could not save the shortcut. Try again."
            return false
        }
        guard onFreehandShortcutChange?(value) == true else {
            message = "That shortcut is already in use. Try another combination."
            return false
        }
        freehandShortcut = value
        UserDefaults.standard.set(data, forKey: "freehandShortcut")
        message = nil
        return true
    }

    func setMenuBarIcon(_ value: Bool) {
        showMenuBarIcon = value
        UserDefaults.standard.set(value, forKey: "showMenuBarIcon")
        onMenuBarChange?(value)
    }

    func setSingleLineText(_ value: Bool) {
        singleLineText = value
        UserDefaults.standard.set(value, forKey: "singleLineText")
    }

    func setCollapseOCRSpaces(_ value: Bool) {
        collapseOCRSpaces = value
        UserDefaults.standard.set(value, forKey: "collapseOCRSpaces")
    }

    func setRecognitionLanguage(_ value: String?) {
        recognitionLanguage = value
        UserDefaults.standard.set(value, forKey: "recognitionLanguage")
    }

    func setTranslateSelectedText(_ value: Bool) {
        if #available(macOS 15.0, *) {
            translateSelectedText = value
            UserDefaults.standard.set(value, forKey: "translateSelectedText")
        } else {
            translateSelectedText = false
            UserDefaults.standard.removeObject(forKey: "translateSelectedText")
        }
    }

    func setTranslationTargetLanguage(_ value: String) {
        translationTargetLanguage = value
        UserDefaults.standard.set(value, forKey: "translationTargetLanguage")
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
    static let windowSize = CGSize(width: 540, height: 790)
    private static let recognitionLanguages = TextCapture.supportedRecognitionLanguages.map { identifier in
        (identifier: identifier, name: Locale.current.localizedString(forIdentifier: identifier) ?? identifier)
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    @ObservedObject var model: SettingsModel
    var onCapture: () -> Void
    var onFreehandCapture: () -> Void
    var onRecordingChange: (Bool) -> Void
    @State private var translationLanguages: [Locale.Language] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(spacing: 7) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14))
                    Text("Word Snip")
                        .font(SettingsFont.demi(24))
                        .padding(.top, 2)
                    Text("Copy text and QR links from anywhere on your Mac")
                        .font(SettingsFont.regular(13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("CAPTURE")
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 13) {
                            settingIcon("keyboard")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Rectangle shortcut").font(SettingsFont.demi(14))
                                Text("Drag a rectangle around text or a QR code")
                                    .font(SettingsFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            ShortcutRecorder(shortcut: model.shortcut, accessibilityLabel: "Rectangle shortcut",
                                             onShortcut: { model.setShortcut($0) },
                                             onInvalid: { model.rejectShortcut() },
                                             onRecordingChange: { recording in
                                                 model.isRecordingShortcut = recording
                                                 if recording { model.message = nil }
                                                 onRecordingChange(recording)
                                             })
                                .frame(width: 160, height: 36)
                        }
                        .padding(.vertical, 13)

                        Divider().padding(.leading, 43)

                        HStack(spacing: 13) {
                            settingIcon("lasso")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Freehand shortcut").font(SettingsFont.demi(14))
                                Text("Draw around text or a QR code")
                                    .font(SettingsFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            ShortcutRecorder(shortcut: model.freehandShortcut, accessibilityLabel: "Freehand shortcut",
                                             onShortcut: { model.setFreehandShortcut($0) },
                                             onInvalid: { model.rejectShortcut() },
                                             onRecordingChange: { recording in
                                                 model.isRecordingShortcut = recording
                                                 if recording { model.message = nil }
                                                 onRecordingChange(recording)
                                             })
                                .frame(width: 160, height: 36)
                        }
                        .padding(.vertical, 13)

                        Divider().padding(.leading, 43)

                        HStack {
                            Text("Click the shortcut, then press your keys")
                                .font(SettingsFont.regular(11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Reset rectangle") {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                                model.setShortcut(.default)
                            }
                                .buttonStyle(.plain)
                                .font(SettingsFont.demi(11))
                                .foregroundStyle(.secondary)
                                .disabled(model.shortcut == .default)
                            Button("Reset freehand") {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                                model.setFreehandShortcut(.defaultFreehand)
                            }
                                .buttonStyle(.plain)
                                .font(SettingsFont.demi(11))
                                .foregroundStyle(.secondary)
                                .disabled(model.freehandShortcut == .defaultFreehand)
                        }
                        .padding(.vertical, 11)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("PREFERENCES")
                    VStack(spacing: 0) {
                        Divider()
                        if !Self.recognitionLanguages.isEmpty {
                            HStack(spacing: 13) {
                                settingIcon("character.bubble")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Text language").font(SettingsFont.demi(14))
                                    Text("Choose a language if detection misses it")
                                        .font(SettingsFont.regular(11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Picker("Text language", selection: Binding(
                                    get: { model.recognitionLanguage },
                                    set: { model.setRecognitionLanguage($0) }
                                )) {
                                    Text("Automatic").tag(nil as String?)
                                    ForEach(Self.recognitionLanguages, id: \.identifier) { language in
                                        Text(language.name).tag(Optional(language.identifier))
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 180, alignment: .trailing)
                            }
                            .padding(.vertical, 11)
                            Divider().padding(.leading, 43)
                        }

                        HStack(spacing: 13) {
                            settingIcon("text.alignleft")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Single-line text").font(SettingsFont.demi(14))
                                Text("Join lines and replace extra spaces with one space")
                                    .font(SettingsFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Single-line text", isOn: Binding(
                                get: { model.singleLineText },
                                set: { model.setSingleLineText($0) }
                            ))
                            .labelsHidden()
                            .tint(.gray)
                        }
                        .padding(.vertical, 11)

                        Divider().padding(.leading, 43)

                        HStack(spacing: 13) {
                            settingIcon("text.alignleft")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Collapse extra spaces").font(SettingsFont.demi(14))
                                Text("Replace repeated spaces while keeping line breaks")
                                    .font(SettingsFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Collapse extra spaces", isOn: Binding(
                                get: { model.collapseOCRSpaces },
                                set: { model.setCollapseOCRSpaces($0) }
                            ))
                            .labelsHidden()
                            .tint(.gray)
                            .disabled(model.singleLineText)
                        }
                        .padding(.vertical, 11)

                        Divider().padding(.leading, 43)

                        HStack(spacing: 13) {
                            settingIcon("translate")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Translate selected text").font(SettingsFont.demi(14))
                                Text(translationAvailable ? "Auto-detect source language and show an overlay" : "Requires macOS 15 or later")
                                    .font(SettingsFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Translate selected text", isOn: Binding(
                                get: { model.translateSelectedText },
                                set: { model.setTranslateSelectedText($0) }
                            ))
                            .labelsHidden()
                            .tint(.gray)
                            .disabled(!translationAvailable)
                        }
                        .padding(.vertical, 11)

                        Divider().padding(.leading, 43)

                        HStack(spacing: 13) {
                            settingIcon("globe")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Translation target").font(SettingsFont.demi(14))
                                Text("Language to translate into")
                                    .font(SettingsFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Picker("Translation target", selection: Binding(
                                get: { model.translationTargetLanguage },
                                set: { model.setTranslationTargetLanguage($0) }
                            )) {
                                ForEach(translationLanguageOptions, id: \.self) { language in
                                    Text(translationLanguageName(language)).tag(language.minimalIdentifier)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 180, alignment: .trailing)
                            .disabled(!translationAvailable || !model.translateSelectedText)
                        }
                        .padding(.vertical, 11)

                        Divider().padding(.leading, 43)

                        HStack(spacing: 13) {
                            settingIcon("menubar.rectangle")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Menu bar icon").font(SettingsFont.demi(14))
                                Text("Open capture modes and Settings from one menu")
                                    .font(SettingsFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Menu bar icon", isOn: Binding(
                                get: { model.showMenuBarIcon },
                                set: { model.setMenuBarIcon($0) }
                            ))
                            .labelsHidden()
                            .tint(.gray)
                        }
                        .padding(.vertical, 11)

                        Divider().padding(.leading, 43)

                        HStack(spacing: 13) {
                            settingIcon("arrow.up.right.square")
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
                            .tint(.gray)
                        }
                        .padding(.vertical, 11)
                        Divider()
                    }
                }

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: model.message == nil ? "info.circle" : "exclamationmark.circle.fill")
                    Text(model.message ?? (model.isRecordingShortcut
                        ? "Press your new shortcut. Esc cancels recording."
                        : "Open Settings anytime with ⌃⌥, even if the menu bar icon is hidden."))
                }
                .font(SettingsFont.regular(11))
                .foregroundStyle(model.message == nil ? Color.secondary : Color.red)
                .frame(minHeight: 22, alignment: .topLeading)

                VStack(spacing: 0) {
                    Divider()
                    captureButton("Capture rectangle", symbol: "viewfinder", shortcut: model.shortcut.title,
                                  action: onCapture)
                        .keyboardShortcut(.defaultAction)
                        .help("Start a rectangular selection")
                    Divider()
                    captureButton("Capture freehand", symbol: "lasso", shortcut: model.freehandShortcut.title,
                                  action: onFreehandCapture)
                        .help("Start a freehand selection")
                }
            }
            .padding(.horizontal, 27)
            .padding(.bottom, 27)
            .padding(.top, 25)
        }
        .task { await loadTranslationLanguages() }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }

    private var translationAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    private var translationLanguageOptions: [Locale.Language] {
        var languages = translationLanguages
        let current = Locale.Language(identifier: model.translationTargetLanguage)
        if !languages.contains(current) { languages.append(current) }
        if languages.isEmpty { languages = [Locale.Language(identifier: "en")] }
        return languages.sorted { translationLanguageName($0).localizedStandardCompare(translationLanguageName($1)) == .orderedAscending }
    }

    private func translationLanguageName(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(SettingsFont.demi(10))
            .tracking(1.1)
            .foregroundStyle(.secondary)
            .padding(.leading, 3)
    }

    private func settingIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
    }

    private func captureButton(_ title: String, symbol: String, shortcut: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                Text(title)
                    .font(SettingsFont.demi(14))
                    .foregroundStyle(.primary)
                Spacer()
                Text(shortcut)
                    .font(SettingsFont.regular(12))
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension SettingsView {
    private func loadTranslationLanguages() async {
        if #available(macOS 15.0, *) {
            let availability = LanguageAvailability()
            let languages = await availability.supportedLanguages
            await MainActor.run { translationLanguages = languages }
        }
    }
}

private enum SettingsFont {
    static func regular(_ size: CGFloat) -> Font { .system(size: size) }
    static func demi(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: CaptureShortcut
    let accessibilityLabel: String
    let onShortcut: (CaptureShortcut) -> Bool
    let onInvalid: () -> Void
    let onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let view = ShortcutRecorderControl()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(accessibilityLabel)
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
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        (isRecording ? NSColor.labelColor : NSColor.separatorColor).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let label = NSAttributedString(string: isRecording ? "Press keys…" : shortcut.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
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
