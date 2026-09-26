import AppKit
import OSLog

enum SelectionMode {
    case rectangle
    case freehand
}

enum SelectionArea {
    case rectangle(CGRect)
    case freehand([CGPoint])

    var bounds: CGRect {
        switch self {
        case .rectangle(let rect): return rect
        case .freehand(let points):
            guard let first = points.first else { return .null }
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            return CGRect(x: xs.min() ?? first.x, y: ys.min() ?? first.y,
                          width: (xs.max() ?? first.x) - (xs.min() ?? first.x),
                          height: (ys.max() ?? first.y) - (ys.min() ?? first.y))
        }
    }
}

@MainActor
final class SelectionOverlay {
    var onSelection: ((NSScreen, SelectionArea) -> Void)?
    var onCancel: (() -> Void)?
    private var windows: [NSWindow] = []
    private var finished = false
    private let mode: SelectionMode
    var hasKeyWindow: Bool { windows.contains(where: \.isKeyWindow) }

    init(mode: SelectionMode) {
        self.mode = mode
    }

    func show() {
        finished = false
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), mode: mode)
            view.onSelection = { [weak self, weak window] area in
                guard let self, let window, !self.finished else { return }
                self.finished = true
                let screenArea: SelectionArea
                switch area {
                case .rectangle(let rect):
                    screenArea = .rectangle(window.convertToScreen(rect))
                case .freehand(let points):
                    screenArea = .freehand(points.map {
                        window.convertToScreen(CGRect(origin: $0, size: .zero)).origin
                    })
                }
                self.close()
                self.onSelection?(screen, screenArea)
            }
            view.onCancel = { [weak self] in
                guard let self, !self.finished else { return }
                self.finished = true
                self.close()
                self.onCancel?()
            }
            window.contentView = view
            window.makeFirstResponder(view)
            let mousePoint = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            if view.bounds.contains(mousePoint) { view.pointerLocation = mousePoint }
            view.needsDisplay = true
            windows.append(window)
            window.orderFrontRegardless()
        }
        if let first = windows.first {
            first.makeKeyAndOrderFront(nil)
            if let view = first.contentView { first.makeFirstResponder(view) }
        }
        NSCursor.crosshair.push()
        NSCursor.crosshair.set()
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
#if DEBUG
    private let captureLog = Logger(subsystem: "com.aldrinnellas.wordsnip.testing", category: "Capture")
#endif
    var onSelection: ((SelectionArea) -> Void)?
    var onCancel: (() -> Void)?
    var pointerLocation: CGPoint? {
        didSet {
            if let oldValue { setNeedsDisplay(hintRect(near: oldValue).insetBy(dx: -2, dy: -2)) }
            if let pointerLocation { setNeedsDisplay(hintRect(near: pointerLocation).insetBy(dx: -2, dy: -2)) }
        }
    }
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var freehandPoints: [CGPoint] = []
    private var pointerTrackingArea: NSTrackingArea?
    private let mode: SelectionMode
    private let hintText: NSAttributedString

    init(frame: CGRect, mode: SelectionMode) {
        self.mode = mode
        hintText = NSAttributedString(
            string: mode == .freehand ? "Draw around text  ·  Esc to cancel" : "Drag to select text  ·  Esc to cancel",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        )
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        let shape: NSBezierPath?
        if mode == .freehand {
            guard let first = freehandPoints.first else { drawIdleHint(); return }
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            path.move(to: first)
            freehandPoints.dropFirst().forEach { path.line(to: $0) }
            if freehandPoints.count > 2 { path.close() }
            shape = path
        } else if let selection = selectionRect, selection.width > 0, selection.height > 0 {
            shape = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        } else {
            shape = nil
        }
        if let shape {
            NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
            shape.fill()
            NSColor.black.withAlphaComponent(0.55).setStroke()
            shape.lineWidth = 3
            shape.stroke()
            NSColor.white.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        drawIdleHint()
    }

    private func drawIdleHint() {
        guard startPoint == nil else { return }
        drawHint(near: pointerLocation ?? CGPoint(x: bounds.midX, y: bounds.midY))
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
#if DEBUG
        captureLog.notice("Selection mouse down")
#endif
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        freehandPoints = mode == .freehand ? [point] : []
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        if mode == .freehand, let currentPoint, bounds.contains(currentPoint),
           let last = freehandPoints.last, hypot(currentPoint.x - last.x, currentPoint.y - last.y) >= 2 {
            freehandPoints.append(currentPoint)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
#if DEBUG
        captureLog.notice("Selection mouse up")
#endif
        currentPoint = convert(event.locationInWindow, from: nil)
        if mode == .freehand {
            if let currentPoint, bounds.contains(currentPoint) { freehandPoints.append(currentPoint) }
            let area = SelectionArea.freehand(freehandPoints)
            guard freehandPoints.count >= 3, area.bounds.width >= 4, area.bounds.height >= 4 else {
                resetSelection()
                return
            }
            onSelection?(area)
            return
        }
        guard let rect = selectionRect, rect.width >= 4, rect.height >= 4 else {
            resetSelection()
            return
        }
        onSelection?(.rectangle(rect))
    }

    private func resetSelection() {
        startPoint = nil
        currentPoint = nil
        freehandPoints = []
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
#if DEBUG
            captureLog.notice("Selection cancelled with Escape")
#endif
            onCancel?()
        }
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
