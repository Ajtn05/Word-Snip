import AppKit
import SwiftUI
import NaturalLanguage

#if canImport(Translation)
import Translation
#endif

#if canImport(_Translation_SwiftUI)
import _Translation_SwiftUI
#endif

private extension Color {
    static let translationPaper = adaptive(light: 0xF5F8FC, dark: 0x202838)
    static let translationToolbar = adaptive(light: 0xFFFFFF, dark: 0x273246)
    static let translationButton = adaptive(light: 0xE7EEF9, dark: 0x3A4860)

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}

@available(macOS 15.0, *)
@MainActor
final class TranslationOverlayModel: ObservableObject {
    let originalText: String
    @Published var targetLanguage: Locale.Language
    @Published var translatedText = ""
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var supportedLanguages: [Locale.Language] = []
    var onTargetChange: (String) -> Void

    init(originalText: String, targetLanguage: Locale.Language, onTargetChange: @escaping (String) -> Void) {
        self.originalText = originalText
        self.targetLanguage = targetLanguage
        self.onTargetChange = onTargetChange
    }
}

@available(macOS 15.0, *)
struct TranslationOverlayView: View {
    @ObservedObject var model: TranslationOverlayModel
    let onClose: () -> Void
    var toolbarInset: CGFloat = 0

    @State private var configuration: TranslationSession.Configuration?
    @State private var generation: Int = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.isLoading && model.translatedText.isEmpty && model.errorMessage == nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Translating…")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } else if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Button("Retry") {
                        retryTranslation()
                    }
                } else {
                    Text(model.translatedText.isEmpty ? model.originalText : model.translatedText)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .padding(.top, toolbarInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.translationPaper)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(.primary.opacity(0.18))
                .allowsHitTesting(false)
        }
        .onExitCommand(perform: onClose)
        .task {
            if configuration == nil {
                configuration = TranslationSession.Configuration(source: nil, target: model.targetLanguage)
            }
            await loadSupportedLanguages()
        }
        .onChange(of: model.targetLanguage) { _, newValue in
            generation += 1
            configuration = TranslationSession.Configuration(source: nil, target: newValue)
            model.isLoading = true
            model.errorMessage = nil
            model.translatedText = ""
            model.onTargetChange(newValue.minimalIdentifier)
        }
        .translationTask(configuration) { session in
            let requestedTarget = model.targetLanguage
            let currentGeneration = generation + 1
            await MainActor.run {
                generation = currentGeneration
                model.isLoading = true
                model.errorMessage = nil
            }
            do {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(model.originalText)
                if let source = recognizer.dominantLanguage,
                   Locale.Language(identifier: source.rawValue).languageCode == requestedTarget.languageCode {
                    guard !Task.isCancelled, generation == currentGeneration,
                          model.targetLanguage == requestedTarget else { return }
                    model.translatedText = model.originalText
                    model.isLoading = false
                    return
                }
                // translate(_:) detects the source from text and handles download prompts.
                // prepareTranslation() cannot detect a nil source and always throws here.
                let response = try await session.translate(model.originalText)
                await MainActor.run {
                    guard !Task.isCancelled, generation == currentGeneration,
                          model.targetLanguage == requestedTarget else { return }
                    if response.sourceLanguage == response.targetLanguage {
                        model.translatedText = model.originalText
                    } else {
                        model.translatedText = response.targetText
                    }
                    model.isLoading = false
                    model.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled, generation == currentGeneration,
                          model.targetLanguage == requestedTarget else { return }
                    model.errorMessage = error.localizedDescription
                    model.isLoading = false
                }
            }
        }
    }

    private func loadSupportedLanguages() async {
        let availability = LanguageAvailability()
        let languages = await availability.supportedLanguages
        await MainActor.run {
            model.supportedLanguages = languages
        }
    }

    private func retryTranslation() {
        generation += 1
        model.isLoading = true
        model.errorMessage = nil
        configuration?.invalidate()
    }
}

@available(macOS 15.0, *)
struct TranslationToolbarView: View {
    @ObservedObject var model: TranslationOverlayModel
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(displayedLanguages, id: \.self) { language in
                    Button {
                        model.targetLanguage = language
                    } label: {
                        if language == model.targetLanguage {
                            Label(displayName(language), systemImage: "checkmark")
                        } else {
                            Text(displayName(language))
                        }
                    }
                }
            } label: {
                Label(displayName(model.targetLanguage), systemImage: "globe")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityLabel("Target language")
            .accessibilityValue(displayName(model.targetLanguage))
            .help("Change target language")

            TranslationCloseButton(onClose: onClose)
                .frame(width: 26, height: 26)
                .background(Color.translationButton, in: Circle())
                .layoutPriority(1)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.translationToolbar, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.primary.opacity(0.2))
                .allowsHitTesting(false)
        }
    }

    private var displayedLanguages: [Locale.Language] {
        if model.supportedLanguages.isEmpty {
            return [model.targetLanguage]
        }
        var languages = model.supportedLanguages
        if !languages.contains(model.targetLanguage) {
            languages.append(model.targetLanguage)
        }
        return languages.sorted { displayName($0).localizedStandardCompare(displayName($1)) == .orderedAscending }
    }

    private func displayName(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }
}

private struct TranslationCloseButton: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.toolTip = "Close translation"
        button.setAccessibilityLabel("Close translation")
        button.target = context.coordinator
        button.action = #selector(Coordinator.close)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onClose = onClose
    }

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    final class Coordinator: NSObject {
        var onClose: () -> Void

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        @objc func close() { onClose() }
    }
}

struct TranslationOverlayLayout {
    let contentFrame: CGRect
    let toolbarFrame: CGRect
    let toolbarInset: CGFloat

    var panelFrame: CGRect { contentFrame.union(toolbarFrame) }

    init(selection: CGRect, visibleFrame: CGRect) {
        // Keep the translation surface at the exact captured screen coordinates.
        contentFrame = selection
        let width = min(168, visibleFrame.width)
        let height: CGFloat = 36
        let gap: CGFloat = 6
        let x = min(max(selection.maxX - width, visibleFrame.minX), visibleFrame.maxX - width)
        let above = selection.maxY + gap
        let below = selection.minY - gap - height
        let y: CGFloat
        if above + height <= visibleFrame.maxY {
            y = above
            toolbarInset = 0
        } else if below >= visibleFrame.minY {
            y = below
            toolbarInset = 0
        } else {
            y = min(selection.maxY, visibleFrame.maxY) - gap - height
            toolbarInset = selection.maxY - y + gap
        }
        toolbarFrame = CGRect(x: x, y: y, width: width, height: height)
    }
}

@available(macOS 15.0, *)
@MainActor
final class TranslationOverlayController {
    private(set) var window: NSPanel?

    func show(originalText: String, selectionBounds: CGRect, screen: NSScreen, targetLanguageIdentifier: String, onTargetChange: @escaping (String) -> Void) {
        close()

        let targetLanguage = Locale.Language(identifier: targetLanguageIdentifier.isEmpty ? "en" : targetLanguageIdentifier)
        let model = TranslationOverlayModel(originalText: originalText, targetLanguage: targetLanguage, onTargetChange: onTargetChange)
        let onClose: () -> Void = { [weak self] in self?.close() }

        let layout = TranslationOverlayLayout(selection: selectionBounds, visibleFrame: screen.visibleFrame)
        let frame = layout.panelFrame
        let panel = TranslationPanel(contentRect: frame,
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.onClose = onClose

        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        let surface = NSHostingView(rootView: TranslationOverlayView(
            model: model, onClose: onClose, toolbarInset: layout.toolbarInset))
        surface.sizingOptions = []
        surface.frame = layout.contentFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        container.addSubview(surface)

        let toolbar = NSHostingView(rootView: TranslationToolbarView(model: model, onClose: onClose))
        toolbar.sizingOptions = []
        toolbar.frame = layout.toolbarFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        container.addSubview(toolbar)
        panel.contentView = container
        panel.setFrame(frame, display: false)

        self.window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.contentView = nil
        window?.orderOut(nil)
        window = nil
    }
}

final class TranslationPanel: NSPanel {
    var onClose: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onClose?() }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
