import AppKit
import SwiftUI
import NaturalLanguage

#if canImport(Translation)
import Translation
#endif

#if canImport(_Translation_SwiftUI)
import _Translation_SwiftUI
#endif

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
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(4)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08)))
        .clipped()
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
        HStack(spacing: 8) {
            Image(systemName: "translate")
                .foregroundStyle(.secondary)
            Picker("Target language", selection: $model.targetLanguage) {
                ForEach(displayedLanguages, id: \.self) { language in
                    Text(displayName(language)).tag(language)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Translate into")

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Close translation")
            .accessibilityLabel("Close translation")
            .keyboardShortcut(.cancelAction)
            .frame(width: 26, height: 26)
            .background(.quaternary, in: Circle())
        }

        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
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

struct TranslationOverlayLayout {
    let contentFrame: CGRect
    let toolbarFrame: CGRect

    init(selection: CGRect, visibleFrame: CGRect) {
        // Keep the translation surface at the exact captured screen coordinates.
        contentFrame = selection
        let width = min(260, visibleFrame.width)
        let height: CGFloat = 40
        let gap: CGFloat = 6
        let x = min(max(selection.maxX - width, visibleFrame.minX), visibleFrame.maxX - width)
        let above = selection.maxY + gap
        // Near the menu bar, place controls below the selection instead of off screen.
        let y = above + height <= visibleFrame.maxY ? above : max(visibleFrame.minY, selection.minY - gap - height)
        toolbarFrame = CGRect(x: x, y: y, width: width, height: height)
    }
}

@available(macOS 15.0, *)
@MainActor
final class TranslationOverlayController {
    private(set) var window: NSPanel?
    private(set) var toolbarWindow: NSPanel?
    private var model: TranslationOverlayModel?

    func show(originalText: String, selectionBounds: CGRect, screen: NSScreen, targetLanguageIdentifier: String, onTargetChange: @escaping (String) -> Void) {
        close()

        let targetLanguage = Locale.Language(identifier: targetLanguageIdentifier.isEmpty ? "en" : targetLanguageIdentifier)
        let newModel = TranslationOverlayModel(originalText: originalText, targetLanguage: targetLanguage, onTargetChange: onTargetChange)
        self.model = newModel

        let layout = TranslationOverlayLayout(selection: selectionBounds, visibleFrame: screen.visibleFrame)
        let panel = TranslationPanel(contentRect: layout.contentFrame,
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.onClose = { [weak self] in self?.close() }

        let view = TranslationOverlayView(model: newModel, onClose: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(layout.contentFrame, display: false)

        let toolbar = TranslationPanel(contentRect: layout.toolbarFrame,
            styleMask: [.borderless], backing: .buffered, defer: false)
        toolbar.isReleasedWhenClosed = false
        toolbar.isFloatingPanel = true
        toolbar.level = panel.level
        toolbar.collectionBehavior = panel.collectionBehavior
        toolbar.isOpaque = false
        toolbar.backgroundColor = .clear
        toolbar.hasShadow = true
        toolbar.hidesOnDeactivate = false
        toolbar.onClose = { [weak self] in self?.close() }
        let controls = NSHostingView(rootView: TranslationToolbarView(model: newModel, onClose: { [weak self] in self?.close() }))
        controls.sizingOptions = []
        toolbar.contentView = controls
        toolbar.setFrame(layout.toolbarFrame, display: false)
        panel.addChildWindow(toolbar, ordered: .above)
        toolbarWindow = toolbar

        self.window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        toolbar.orderFrontRegardless()
    }

    func close() {
        if let toolbarWindow {
            window?.removeChildWindow(toolbarWindow)
            toolbarWindow.contentView = nil
            toolbarWindow.orderOut(nil)
        }
        toolbarWindow = nil
        window?.contentView = nil
        window?.orderOut(nil)
        window = nil
        model = nil
    }
}

final class TranslationPanel: NSPanel {
    var onClose: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onClose?() }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
