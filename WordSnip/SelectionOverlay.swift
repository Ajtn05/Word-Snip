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
            window.acceptsMouseMovedEvents = true
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
            let mousePoint = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            if view.bounds.contains(mousePoint) { view.pointerLocation = mousePoint }
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
    var pointerLocation: CGPoint? {
        didSet {
            if let oldValue { setNeedsDisplay(hintRect(near: oldValue).insetBy(dx: -2, dy: -2)) }
            if let pointerLocation { setNeedsDisplay(hintRect(near: pointerLocation).insetBy(dx: -2, dy: -2)) }
        }
    }
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var pointerTrackingArea: NSTrackingArea?
    private let hintText = NSAttributedString(string: "Drag to select text  ·  Esc to cancel", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white
    ])

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        if let selection = selectionRect, selection.width > 0, selection.height > 0 {
            NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
            selection.fill()
            NSColor.black.withAlphaComponent(0.55).setStroke()
            let contrastOutline = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            contrastOutline.lineWidth = 3
            contrastOutline.stroke()
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.stroke()
        }
        if startPoint == nil, let pointerLocation { drawHint(near: pointerLocation) }
    }

    private func drawHint(near point: CGPoint) {
        let pillRect = hintRect(near: point)
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.82).setFill()
        pill.fill()
        NSColor.white.withAlphaComponent(0.20).setStroke()
        pill.lineWidth = 1
        pill.stroke()
        hintText.draw(at: CGPoint(x: pillRect.minX + 10, y: pillRect.minY + (pillRect.height - hintText.size().height) / 2))
    }

    private func hintRect(near point: CGPoint) -> CGRect {
        let width = hintText.size().width + 20
        let height: CGFloat = 28
        let preferredX = point.x + 18 + width + 12 <= bounds.maxX ? point.x + 18 : point.x - width - 18
        let x = min(max(12, preferredX), max(12, bounds.maxX - width - 12))
        let y = point.y >= height + 22 ? point.y - height - 14 : point.y + 18
        return CGRect(x: x, y: y, width: width, height: height)
    }

    override func mouseEntered(with event: NSEvent) {
        pointerLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseExited(with event: NSEvent) {
        pointerLocation = nil
    }

    override func mouseMoved(with event: NSEvent) {
        pointerLocation = convert(event.locationInWindow, from: nil)
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
            pointerLocation = convert(event.locationInWindow, from: nil)
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
