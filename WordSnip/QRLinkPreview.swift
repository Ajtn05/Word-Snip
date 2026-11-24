import AppKit
import SwiftUI

@MainActor
final class QRLinkPreviewModel: ObservableObject {
    @Published var url: URL

    init(url: URL) {
        self.url = url
    }
}

struct QRLinkPreviewView: View {
    @ObservedObject var model: QRLinkPreviewModel
    let onOpen: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scanned link")
                .font(.headline)

            ScrollView {
                Text(model.url.absoluteString)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 60, maxHeight: 160)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Open in default browser") {
                    onOpen(model.url)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 220)
    }
}

@MainActor
final class QRLinkPreviewController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: QRLinkPreviewModel?
    var onOpen: ((URL) -> Void)?

    func show(url: URL) {
        if let existingModel = model, let existingWindow = window {
            existingModel.url = url
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let newModel = QRLinkPreviewModel(url: url)
        self.model = newModel

        let view = QRLinkPreviewView(model: newModel) { [weak self] url in
            self?.onOpen?(url)
        }
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 240),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scanned Link"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()

        window.delegate = self

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else { return }
        window = nil
        model = nil
    }

}
