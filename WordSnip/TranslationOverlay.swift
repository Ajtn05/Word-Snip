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

    @State private var translatedText: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var configuration: TranslationSession.Configuration?
    @State private var generation: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("Target language", selection: $model.targetLanguage) {
                    ForEach(displayedLanguages, id: \.self) { language in
                        Text(displayName(language)).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if isLoading && translatedText.isEmpty && errorMessage == nil {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Translating…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                        Button("Retry") {
                            retryTranslation()
                        }
                    } else {
                        Text(translatedText.isEmpty ? model.originalText : translatedText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(4)
            }
        }
        .padding(12)
        .frame(minWidth: 220, minHeight: 140)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .task {
            if configuration == nil {
                configuration = TranslationSession.Configuration(source: nil, target: model.targetLanguage)
            }
            await loadSupportedLanguages()
        }
        .onChange(of: model.targetLanguage) { _, newValue in
            generation += 1
            configuration = TranslationSession.Configuration(source: nil, target: newValue)
            isLoading = true
            errorMessage = nil
            translatedText = ""
            model.onTargetChange(newValue.minimalIdentifier)
        }
        .translationTask(configuration) { session in
            let requestedTarget = model.targetLanguage
            let currentGeneration = generation + 1
            await MainActor.run {
                generation = currentGeneration
                isLoading = true
                errorMessage = nil
            }
            do {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(model.originalText)
                if let source = recognizer.dominantLanguage,
                   Locale.Language(identifier: source.rawValue).languageCode == requestedTarget.languageCode {
                    guard !Task.isCancelled, generation == currentGeneration,
                          model.targetLanguage == requestedTarget else { return }
                    translatedText = model.originalText
                    isLoading = false
                    return
                }
                try await session.prepareTranslation()
                let response = try await session.translate(model.originalText)
                await MainActor.run {
                    guard !Task.isCancelled, generation == currentGeneration,
                          model.targetLanguage == requestedTarget else { return }
                    if response.sourceLanguage == response.targetLanguage {
                        translatedText = model.originalText
                    } else {
                        translatedText = response.targetText
                    }
                    isLoading = false
                    errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled, generation == currentGeneration,
                          model.targetLanguage == requestedTarget else { return }
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
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

    private func loadSupportedLanguages() async {
        let availability = LanguageAvailability()
        let languages = await availability.supportedLanguages
        await MainActor.run {
            model.supportedLanguages = languages
        }
    }

    private func retryTranslation() {
        generation += 1
        isLoading = true
        errorMessage = nil
        configuration?.invalidate()
    }
}

@available(macOS 15.0, *)
@MainActor
final class TranslationOverlayController {
    private var window: NSPanel?
    private var model: TranslationOverlayModel?

    func show(originalText: String, selectionBounds: CGRect, screen: NSScreen, targetLanguageIdentifier: String, onTargetChange: @escaping (String) -> Void) {
        close()

        let targetLanguage = Locale.Language(identifier: targetLanguageIdentifier.isEmpty ? "en" : targetLanguageIdentifier)
        let newModel = TranslationOverlayModel(originalText: originalText, targetLanguage: targetLanguage, onTargetChange: onTargetChange)
        self.model = newModel

        let usable = screen.visibleFrame
        let minWidth: CGFloat = 220
        let minHeight: CGFloat = 140
        let width = min(max(selectionBounds.width, minWidth), usable.width)
        let height = min(max(selectionBounds.height, minHeight), usable.height)

        var originX = selectionBounds.minX
        var originY = selectionBounds.minY
        originX = min(max(originX, usable.minX), usable.maxX - width)
        originY = min(max(originY, usable.minY), usable.maxY - height)

        let panel = TranslationPanel(contentRect: CGRect(x: originX, y: originY, width: width, height: height),
                            styleMask: [.borderless, .resizable],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentMinSize = NSSize(width: minWidth, height: minHeight)

        let view = TranslationOverlayView(model: newModel, onClose: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting

        self.window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.contentView = nil
        window?.orderOut(nil)
        window = nil
        model = nil
    }
}

final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
