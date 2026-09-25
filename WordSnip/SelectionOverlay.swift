import AppKit

@MainActor
final class SelectionOverlay {
    var onSelection: ((NSScreen, CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var windows: [NSWindow] = []
    private var finished = false

    func show() {
        finished = false
        for screen in NSScreen.screens {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onSelection = { [weak self, weak window] rect in
                guard let self, let window, !self.finished else { return }
                self.finished = true
                let screenRect = window.convertToScreen(rect)
                self.close()
                self.onSelection?(screen, screenRect)
            }
            view.onCancel = { [weak self] in
                guard let self, !self.finished else { return }
                self.finished = true
                self.close()
                self.onCancel?()
            }
            window.contentView = view
            windows.append(window)
            window.orderFrontRegardless()
        }
        if let first = windows.first {
            NSApp.activate(ignoringOtherApps: true)
            first.makeKeyAndOrderFront(nil)
        }
        NSCursor.crosshair.push()
    }

    func close() {
        guard !windows.isEmpty else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.pop()
    }
}

private final class SelectionWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        if let selection = selectionRect, selection.width > 0, selection.height > 0 {
            NSGraphicsContext.current?.compositingOperation = .clear
            selection.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.stroke()
        } else {
            let instruction = "Drag to select text  •  Esc to cancel"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.65)
            ]
            let text = NSAttributedString(string: instruction, attributes: attributes)
            let size = text.size()
            text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: bounds.midY + 20))
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width >= 4, rect.height >= 4 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }
        onSelection?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
        else { super.keyDown(with: event) }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(x: min(startPoint.x, currentPoint.x),
                      y: min(startPoint.y, currentPoint.y),
                      width: abs(startPoint.x - currentPoint.x),
                      height: abs(startPoint.y - currentPoint.y)).intersection(bounds)
    }
}
