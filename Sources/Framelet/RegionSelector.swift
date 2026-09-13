import AppKit
import RecorderCore

@MainActor
final class RegionSelector {
    private var panels: [SelectionPanel] = []
    private var selectedPanel: SelectionPanel?
    private var previousApp: NSRunningApplication?
    var onRecord: ((CaptureRegion, NSScreen) -> Void)?
    var onCancel: (() -> Void)?

    func show() {
        close()
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        for screen in NSScreen.screens {
            let panel = SelectionPanel(screen: screen)
            panel.selectionView.onSelect = { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.selectedPanel = panel
                for other in self.panels where other !== panel {
                    other.selectionView.clear()
                }
                panel.makeKey()
            }
            panel.selectionView.onRecord = { [weak self, weak panel] rect in
                guard let self, let panel,
                      let region = CaptureRegion(
                        rect: rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY),
                        displayBounds: screen.frame
                      ) else { return }
                self.selectedPanel = panel
                self.onRecord?(region, screen)
            }
            panel.selectionView.onCancel = { [weak self] in self?.onCancel?() }
            panels.append(panel)
            panel.orderFrontRegardless()
            if screen.frame.contains(NSEvent.mouseLocation) { panel.makeKey() }
        }
    }

    func setRecording(dimOutside: Bool) {
        for panel in panels {
            if panel !== selectedPanel {
                panel.orderOut(nil)
            } else {
                panel.selectionView.setRecording(dimOutside: dimOutside)
                panel.ignoresMouseEvents = true
                panel.resignKey()
            }
        }
        previousApp?.activate()
    }

    func close() {
        for panel in panels {
            panel.selectionView.stopAnimation()
            panel.close()
        }
        panels.removeAll()
        selectedPanel = nil
    }
}

@MainActor
private final class SelectionPanel: NSPanel {
    let selectionView: SelectionView

    init(screen: NSScreen) {
        selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = selectionView
        makeFirstResponder(selectionView)
    }

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, [36, 49, 53, 76].contains(event.keyCode),
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            selectionView.keyDown(with: event)
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
private final class SelectionView: NSView {
    var onSelect: (() -> Void)?
    var onRecord: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var selection = CGRect.zero
    private var startPoint = CGPoint.zero
    private var originalRect = CGRect.zero
    private var dragMode = DragMode.draw
    private var phase: CGFloat = 0
    private var timer: Timer?
    private var recording = false
    private var dimOutside = true
    private let toolbar = NSVisualEffectView()
    private let dimensions = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "Record", target: nil, action: nil)
    private enum DragMode { case draw, move, resize(Int) }

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolbar.material = .hudWindow
        toolbar.blendingMode = .behindWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 8
        toolbar.isHidden = true
        dimensions.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        dimensions.alignment = .center
        dimensions.frame = CGRect(x: 8, y: 12, width: 112, height: 18)
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = CGRect(x: 124, y: 7, width: 76, height: 30)
        cancelButton.toolTip = "Cancel (Escape)"
        recordButton.target = self
        recordButton.action = #selector(record)
        recordButton.bezelStyle = .rounded
        recordButton.contentTintColor = .systemRed
        recordButton.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil)
        recordButton.imagePosition = .imageLeading
        recordButton.frame = CGRect(x: 202, y: 7, width: 94, height: 30)
        recordButton.toolTip = "Record (Space or Return)"
        toolbar.addSubview(dimensions)
        toolbar.addSubview(cancelButton)
        toolbar.addSubview(recordButton)
        addSubview(toolbar)
        setAccessibilityLabel("Screen recording region")
        let timer = Timer(timeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phase = (self.phase + 0.7).truncatingRemainder(dividingBy: 12)
                self.needsDisplay = true
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func stopAnimation() { timer?.invalidate(); timer = nil }

    func clear() {
        selection = .zero
        toolbar.isHidden = true
        needsDisplay = true
    }

    func setRecording(dimOutside: Bool) {
        recording = true
        self.dimOutside = dimOutside
        stopAnimation()
        toolbar.isHidden = true
        needsDisplay = true
    }

    override func resetCursorRects() {
        guard !recording else { return }
        addCursorRect(bounds, cursor: .crosshair)
        if !selection.isEmpty { addCursorRect(selection.insetBy(dx: 8, dy: 8), cursor: .openHand) }
        for (index, point) in handles.enumerated() {
            let cursor: NSCursor = [1, 5].contains(index) ? .resizeUpDown : .resizeLeftRight
            addCursorRect(CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14), cursor: cursor)
        }
        if !toolbar.isHidden { addCursorRect(toolbar.frame, cursor: .arrow) }
    }

    private var handles: [CGPoint] {
        guard !selection.isEmpty else { return [] }
        return [
            CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.midX, y: selection.minY),
            CGPoint(x: selection.maxX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.midY),
            CGPoint(x: selection.maxX, y: selection.maxY), CGPoint(x: selection.midX, y: selection.maxY),
            CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.minX, y: selection.midY)
        ]
    }

    override func draw(_ dirtyRect: NSRect) {
        let mask = NSBezierPath(rect: bounds)
        if !selection.isEmpty { mask.appendRect(selection) }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(recording ? (dimOutside ? 0.055 : 0) : 0.22).setFill()
        mask.fill()
        guard !selection.isEmpty else { return }
        let border = NSBezierPath(rect: selection.insetBy(dx: -1, dy: -1))
        border.lineWidth = 2
        if recording {
            NSColor.systemRed.setStroke()
            border.stroke()
            return
        }
        NSColor.white.setStroke()
        border.stroke()
        NSColor.black.withAlphaComponent(0.85).setStroke()
        border.setLineDash([6, 6], count: 2, phase: phase)
        border.stroke()
        for point in handles {
            let handle = NSBezierPath(roundedRect: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8), xRadius: 2, yRadius: 2)
            NSColor.white.setFill()
            handle.fill()
            NSColor.black.withAlphaComponent(0.65).setStroke()
            handle.lineWidth = 1
            handle.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !recording else { return }
        onSelect?()
        window?.makeFirstResponder(self)
        startPoint = convert(event.locationInWindow, from: nil)
        originalRect = selection
        if let index = handles.firstIndex(where: { hypot($0.x - startPoint.x, $0.y - startPoint.y) < 10 }) {
            dragMode = .resize(index)
        } else if selection.contains(startPoint) {
            dragMode = .move
        } else {
            dragMode = .draw
            selection = .zero
        }
        toolbar.isHidden = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !recording else { return }
        let raw = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: min(max(raw.x, 0), bounds.width), y: min(max(raw.y, 0), bounds.height))
        switch dragMode {
        case .draw:
            selection = CGRect(x: min(point.x, startPoint.x), y: min(point.y, startPoint.y),
                               width: abs(point.x - startPoint.x), height: abs(point.y - startPoint.y)).integral
        case .move:
            selection.origin = CGPoint(
                x: min(max(0, originalRect.minX + point.x - startPoint.x), bounds.width - selection.width),
                y: min(max(0, originalRect.minY + point.y - startPoint.y), bounds.height - selection.height)
            )
        case .resize(let index):
            var left = originalRect.minX
            var right = originalRect.maxX
            var bottom = originalRect.minY
            var top = originalRect.maxY
            if [0, 6, 7].contains(index) { left = min(point.x, right - 16) }
            if [2, 3, 4].contains(index) { right = max(point.x, left + 16) }
            if [0, 1, 2].contains(index) { bottom = min(point.y, top - 16) }
            if [4, 5, 6].contains(index) { top = max(point.y, bottom + 16) }
            selection = CGRect(x: left, y: bottom, width: right - left, height: top - bottom).integral
        }
        if selection.width >= 16 && selection.height >= 16 { updateToolbar() }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !recording else { return }
        if selection.width < 16 || selection.height < 16 { clear(); return }
        updateToolbar()
        window?.invalidateCursorRects(for: self)
    }

    private func updateToolbar() {
        dimensions.stringValue = "\(Int(selection.width)) \u{00d7} \(Int(selection.height)) pt"
        let below = selection.minY - 54
        let vertical = below >= 8 ? below : min(bounds.height - 52, selection.maxY + 10)
        toolbar.frame = CGRect(x: max(8, min(selection.midX - 152, bounds.width - 312)), y: vertical, width: 304, height: 44)
        toolbar.isHidden = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: cancel()
        case 36, 49, 76: record()
        default: super.keyDown(with: event)
        }
    }

    @objc private func cancel() { if !recording { onCancel?() } }
    @objc private func record() {
        if !recording && selection.width >= 16 && selection.height >= 16 { onRecord?(selection) }
    }
}

extension RegionSelector {
    static func checkInteractions(snapshots: URL) throws {
        let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        defer { view.stopAnimation(); window.close() }
        var recorded: CGRect?
        var cancelled = false
        view.onRecord = { recorded = $0 }
        view.onCancel = { cancelled = true }

        func drag(from start: CGPoint, to end: CGPoint) {
            func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            view.mouseDown(with: event(.leftMouseDown, start))
            view.mouseDragged(with: event(.leftMouseDragged, end))
            view.mouseUp(with: event(.leftMouseUp, end))
        }

        func key(_ code: UInt16) {
            view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                               windowNumber: window.windowNumber, context: nil, characters: " ",
                                               charactersIgnoringModifiers: " ", isARepeat: false, keyCode: code)!)
        }

        drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 500, y: 350))
        key(49)
        guard recorded == CGRect(x: 100, y: 100, width: 400, height: 250) else {
            throw RecorderError.message("Drawing a selection or the Space shortcut failed")
        }
        drag(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 350, y: 225))
        key(36)
        guard recorded == CGRect(x: 150, y: 125, width: 400, height: 250) else {
            throw RecorderError.message("Moving a selection or the Return shortcut failed")
        }
        drag(from: CGPoint(x: 150, y: 125), to: CGPoint(x: 140, y: 105))
        key(36)
        guard recorded == CGRect(x: 140, y: 105, width: 410, height: 270) else {
            throw RecorderError.message("Resizing a corner handle failed")
        }
        key(53)
        guard cancelled else { throw RecorderError.message("Escape must cancel selection") }

        func snapshot(_ name: String) throws {
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw RecorderError.message("Could not create overlay snapshot")
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let outsideAlpha = bitmap.colorAt(x: 20, y: 20)?.alphaComponent ?? 1
            let insideAlpha = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent ?? 1
            guard insideAlpha < 0.01, outsideAlpha > 0.01, outsideAlpha < 0.3 else {
                throw RecorderError.message("The overlay must be transparent inside the selection and subtly dimmed outside")
            }
            if name == "recording.png" {
                let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
                for vertical in 160..<300 {
                    guard let color = bitmap.colorAt(x: Int(139 * scale), y: Int((600 - CGFloat(vertical)) * scale))?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.8,
                          color.redComponent > color.greenComponent + 0.2,
                          color.redComponent > color.blueComponent + 0.2 else {
                        throw RecorderError.message("Recording border must be continuously solid red, without marching-ant gaps")
                    }
                }
            }
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw RecorderError.message("Could not encode overlay snapshot")
            }
            try png.write(to: snapshots.appendingPathComponent(name))
        }

        try snapshot("selection.png")
        recorded = nil
        view.setRecording(dimOutside: true)
        key(49)
        guard recorded == nil else { throw RecorderError.message("Recording overlay must not restart capture") }
        try snapshot("recording.png")
        print("PASS: draw, move, resize, Space, Return, Escape, locked selection, overlay alpha pixels, and solid recording border")
    }
}