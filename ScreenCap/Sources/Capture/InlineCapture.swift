import Cocoa
import ScreenCaptureKit
import UniformTypeIdentifiers

/// flameshot-style capture: freeze the focused display, select, annotate in place, Cmd+C to copy.
/// Nothing is written to disk unless the user explicitly saves.
final class InlineCaptureController {
    var onPin: ((NSImage) -> Void)?
    private var session: InlineCaptureSession?
    private var starting = false

    func start() {
        guard session == nil, !starting, let screen = Self.focusedScreen() else { return }
        starting = true
        let previousApp = NSWorkspace.shared.frontmostApplication
        Task { @MainActor [weak self] in
            defer { self?.starting = false }
            do {
                let frozen = try await Self.captureDisplay(screen)
                self?.present(frozen: frozen, screen: screen, previousApp: previousApp)
            } catch {
                Toast.show(message: "Capture failed. Check Screen Recording permission.", style: .error)
            }
        }
    }

    private func present(frozen: CGImage, screen: NSScreen, previousApp: NSRunningApplication?) {
        let session = InlineCaptureSession(frozen: frozen, screen: screen)
        session.onPin = { [weak self] image in self?.onPin?(image) }
        session.onFinished = { [weak self] in
            // Dropping the session releases the frozen full-display image.
            self?.session = nil
            if let previousApp, !previousApp.isTerminated { previousApp.activate() }
        }
        self.session = session
        session.show()
    }

    /// The display holding the frontmost app's frontmost window; the cursor's display as fallback.
    static func focusedScreen() -> NSScreen? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in windows {
                guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                      (info[kCGWindowLayer as String] as? Int) == 0,
                      let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
                // Window bounds are CG global (top-left origin); NSScreen frames are bottom-left.
                let center = NSPoint(x: bounds.midX, y: NSScreen.primaryHeight - bounds.midY)
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
                    return screen
                }
            }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    }

    static func captureDisplay(_ screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

// MARK: - Session

final class InlineCaptureSession: NSObject {
    var onPin: ((NSImage) -> Void)?
    var onFinished: (() -> Void)?

    private static let defaultColor = NSColor(srgbRed: 1, green: 0x05 / 255, blue: 0, alpha: 1)
    private static let palette: [NSColor] = [
        defaultColor, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .black, .white,
    ]

    private let frozen: CGImage
    private let window: InlineOverlayWindow
    private let canvas: InlineCanvas
    private let dimView: SelectionDimView
    private let toolbar = InlineToolbar()
    private var paletteView: NSView?
    private var finished = false

    init(frozen: CGImage, screen: NSScreen) {
        self.frozen = frozen
        let bounds = NSRect(origin: .zero, size: screen.frame.size)
        window = InlineOverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        canvas = InlineCanvas(frame: bounds)
        dimView = SelectionDimView(frame: bounds)
        super.init()

        let container = NSView(frame: bounds)
        container.wantsLayer = true
        let background = NSImageView(frame: bounds)
        background.image = NSImage(cgImage: frozen, size: bounds.size)
        background.imageScaling = .scaleAxesIndependently
        container.addSubview(background)

        canvas.baseImage = NSImage(cgImage: frozen, size: bounds.size)
        canvas.drawsBaseImage = false
        canvas.currentColor = Self.defaultColor
        canvas.currentLineWidth = 2
        canvas.currentTool = .select
        container.addSubview(canvas)

        dimView.pixelScale = CGFloat(frozen.width) / bounds.width
        container.addSubview(dimView)

        toolbar.isHidden = true
        toolbar.setActiveTool(.select, filled: false)
        toolbar.setColor(Self.defaultColor)
        container.addSubview(toolbar)

        window.contentView = container
        window.level = .screenSaver
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        canvas.onSelectionChanged = { [weak self] in self?.selectionChanged() }
        canvas.onCopy = { [weak self] in self?.copyAndClose() }
        canvas.onSave = { [weak self] in self?.saveAndClose() }
        canvas.onCancel = { [weak self] in self?.finish() }
        toolbar.onAction = { [weak self] action in self?.handle(action) }
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    private func selectionChanged() {
        dimView.selection = canvas.selection
        guard let selection = canvas.selection, !canvas.isAdjustingSelection else {
            toolbar.isHidden = true
            hidePalette()
            return
        }
        toolbar.position(for: selection, in: canvas.bounds)
        toolbar.isHidden = false
    }

    private func handle(_ action: InlineToolbar.Action) {
        switch action {
        case .tool(let tool, let filled):
            canvas.endTextEditing()
            canvas.currentTool = tool
            canvas.currentFilled = filled
            toolbar.setActiveTool(tool, filled: filled)
            hidePalette()
        case .color:
            paletteView == nil ? showPalette() : hidePalette()
        case .undo:
            canvas.endTextEditing()
            canvas.performUndo()
        case .redo:
            canvas.endTextEditing()
            canvas.performRedo()
        case .copy:
            copyAndClose()
        case .save:
            saveAndClose()
        case .pin:
            pinAndClose()
        case .close:
            finish()
        }
        window.makeFirstResponder(canvas)
    }

    // MARK: Palette

    private func showPalette() {
        let size: CGFloat = 22
        let gap: CGFloat = 6
        let view = NSView(frame: NSRect(x: 0, y: 0,
                                        width: CGFloat(Self.palette.count) * (size + gap) + gap,
                                        height: size + gap * 2))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        view.layer?.cornerRadius = 8
        for (index, color) in Self.palette.enumerated() {
            let swatch = NSButton(frame: NSRect(x: gap + CGFloat(index) * (size + gap), y: gap, width: size, height: size))
            swatch.isBordered = false
            swatch.title = ""
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = color.cgColor
            swatch.layer?.cornerRadius = size / 2
            swatch.layer?.borderColor = NSColor.white.cgColor
            swatch.layer?.borderWidth = color == canvas.currentColor ? 2 : 0.5
            swatch.tag = index
            swatch.target = self
            swatch.action = #selector(pickColor(_:))
            view.addSubview(swatch)
        }
        let anchor = toolbar.convert(toolbar.colorButtonFrame, to: toolbar.superview)
        var origin = NSPoint(x: anchor.midX - view.frame.width / 2, y: toolbar.frame.maxY + 8)
        if origin.y + view.frame.height > canvas.bounds.maxY { origin.y = toolbar.frame.minY - view.frame.height - 8 }
        origin.x = min(max(origin.x, 8), canvas.bounds.maxX - view.frame.width - 8)
        view.setFrameOrigin(origin)
        toolbar.superview?.addSubview(view)
        paletteView = view
    }

    private func hidePalette() {
        paletteView?.removeFromSuperview()
        paletteView = nil
    }

    @objc private func pickColor(_ sender: NSButton) {
        guard Self.palette.indices.contains(sender.tag) else { return }
        let color = Self.palette[sender.tag]
        canvas.currentColor = color
        toolbar.setColor(color)
        hidePalette()
        window.makeFirstResponder(canvas)
    }

    // MARK: Output

    private func copyAndClose() {
        guard let image = renderSelection(), let png = Self.pngData(image) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        // Some apps only read TIFF from the pasteboard.
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        finish()
        Toast.show(message: "Copied to clipboard")
    }

    private func saveAndClose() {
        guard let image = renderSelection(), let png = Self.pngData(image) else { return }
        do {
            let url = try Self.writeExclusive(png, in: Defaults.shared.saveLocation)
            Defaults.shared.addRecentCapture(url)
            finish()
            Toast.show(message: "Saved to \(url.deletingLastPathComponent().lastPathComponent)")
        } catch {
            Toast.show(message: "Could not save the screenshot", style: .error)
        }
    }

    private func pinAndClose() {
        guard let image = renderSelection(), let selection = canvas.selection else { return }
        let pinned = NSImage(cgImage: image, size: selection.size)
        finish()
        onPin?(pinned)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        hidePalette()
        window.orderOut(nil)
        window.contentView = nil
        onFinished?()
    }

    /// Crops the frozen display to the selection at full pixel resolution and composites the annotations.
    private func renderSelection() -> CGImage? {
        canvas.endTextEditing()
        guard let selection = canvas.selection?.intersection(canvas.bounds),
              selection.width >= 1, selection.height >= 1 else { return nil }
        let scale = CGFloat(frozen.width) / canvas.bounds.width
        let pixelRect = CGRect(x: selection.minX * scale, y: selection.minY * scale,
                               width: selection.width * scale, height: selection.height * scale).integral
        let space = frozen.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: Int(pixelRect.width), height: Int(pixelRect.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: -pixelRect.minX, y: -pixelRect.minY)
        context.draw(frozen, in: CGRect(x: 0, y: 0, width: frozen.width, height: frozen.height))
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        canvas.drawAnnotations(in: context)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// PNG with no metadata beyond what ImageIO requires.
    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Creates the file with O_EXCL and mode 0600 in one step, so it never overwrites and is never world-readable.
    static func writeExclusive(_ data: Data, in directory: URL, now: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Screenshot \(formatter.string(from: now))"
        for attempt in 0..<20 {
            let name = attempt == 0 ? "\(base).png" : "\(base) (\(attempt + 1)).png"
            let url = directory.appendingPathComponent(name)
            let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
            if fd < 0 {
                if errno == EEXIST { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            do {
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
            return url
        }
        throw POSIXError(.EEXIST)
    }
}

// MARK: - Window

final class InlineOverlayWindow: NSWindow {
    // Borderless windows refuse key status by default, which would drop every keystroke.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Canvas

fileprivate enum SelectionHandle: CaseIterable {
    case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left
}

/// Annotation canvas spanning the whole display; the selection only decides what gets exported.
final class InlineCanvas: AnnotationCanvas {
    private enum Drag {
        case none
        case creating(NSPoint)
        case moving(NSPoint)
        case resizing(SelectionHandle, NSRect)
    }

    private(set) var selection: NSRect?
    private(set) var isAdjustingSelection = false
    var onSelectionChanged: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    private var drag: Drag = .none
    private var scrollAccumulator: CGFloat = 0
    private static let handleRadius: CGFloat = 8
    private static let minimumSide: CGFloat = 3

    fileprivate static func handlePoints(_ r: NSRect) -> [(SelectionHandle, NSPoint)] {
        [
            (.bottomLeft, NSPoint(x: r.minX, y: r.minY)), (.bottom, NSPoint(x: r.midX, y: r.minY)),
            (.bottomRight, NSPoint(x: r.maxX, y: r.minY)), (.right, NSPoint(x: r.maxX, y: r.midY)),
            (.topRight, NSPoint(x: r.maxX, y: r.maxY)), (.top, NSPoint(x: r.midX, y: r.maxY)),
            (.topLeft, NSPoint(x: r.minX, y: r.maxY)), (.left, NSPoint(x: r.minX, y: r.midY)),
        ]
    }

    /// Commits an in-progress text annotation by taking first responder back from the field editor.
    func endTextEditing() {
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = clamp(convert(event.locationInWindow, from: nil))
        guard let current = selection else {
            beginCreating(at: point)
            return
        }
        if let handle = handle(at: point, in: current) {
            endTextEditing()
            begin(.resizing(handle, current))
            return
        }
        if current.contains(point) {
            if currentTool == .select, !annotations.contains(where: { $0.hitTest(point: point) }) {
                endTextEditing()
                begin(.moving(point))
                return
            }
            super.mouseDown(with: event)
            return
        }
        // Outside the selection a new one starts only while nothing is drawn, so a stray click can't discard work.
        if annotations.isEmpty {
            beginCreating(at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamp(convert(event.locationInWindow, from: nil))
        switch drag {
        case .none:
            super.mouseDragged(with: event)
        case .creating(let start):
            var rect = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                              width: abs(point.x - start.x), height: abs(point.y - start.y))
            if NSEvent.modifierFlags.contains(.shift) {
                let side = max(rect.width, rect.height)
                rect.size = NSSize(width: side, height: side)
            }
            selection = rect.intersection(bounds)
            onSelectionChanged?()
        case .moving(let last):
            guard var rect = selection else { return }
            rect.origin.x = min(max(rect.origin.x + point.x - last.x, 0), bounds.width - rect.width)
            rect.origin.y = min(max(rect.origin.y + point.y - last.y, 0), bounds.height - rect.height)
            selection = rect
            drag = .moving(point)
            onSelectionChanged?()
        case .resizing(let handle, let original):
            selection = Self.resized(original, handle: handle, to: point)
            onSelectionChanged?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case .none = drag {
            super.mouseUp(with: event)
            return
        }
        drag = .none
        isAdjustingSelection = false
        if let s = selection, s.width < Self.minimumSide || s.height < Self.minimumSide {
            selection = nil
        }
        onSelectionChanged?()
    }

    /// Scroll changes stroke thickness, as in flameshot.
    override func scrollWheel(with event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY
        guard abs(scrollAccumulator) >= 4 else { return }
        currentLineWidth = min(max(currentLineWidth + (scrollAccumulator > 0 ? 1 : -1), 1), 20)
        scrollAccumulator = 0
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown, flags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            onCopy?()
            return true
        case "s":
            onSave?()
            return true
        case "z":
            endTextEditing()
            if flags.contains(.shift) { performRedo() } else { performUndo() }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()      // Esc
        case 36, 76: onCopy?()    // Return, keypad Enter
        default: super.keyDown(with: event)
        }
    }

    private func beginCreating(at point: NSPoint) {
        endTextEditing()
        selection = NSRect(origin: point, size: .zero)
        begin(.creating(point))
    }

    private func begin(_ newDrag: Drag) {
        drag = newDrag
        isAdjustingSelection = true
        onSelectionChanged?()
    }

    private func handle(at point: NSPoint, in rect: NSRect) -> SelectionHandle? {
        Self.handlePoints(rect).first { hypot($0.1.x - point.x, $0.1.y - point.y) <= Self.handleRadius }?.0
    }

    private func clamp(_ p: NSPoint) -> NSPoint {
        NSPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    fileprivate static func resized(_ r: NSRect, handle: SelectionHandle, to p: NSPoint) -> NSRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch handle {
        case .bottomLeft: minX = p.x; minY = p.y
        case .bottom: minY = p.y
        case .bottomRight: maxX = p.x; minY = p.y
        case .right: maxX = p.x
        case .topRight: maxX = p.x; maxY = p.y
        case .top: maxY = p.y
        case .topLeft: minX = p.x; maxY = p.y
        case .left: minX = p.x
        }
        return NSRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }
}

// MARK: - Dim layer

/// Dims everything outside the selection and draws its border, handles and pixel size. Never takes mouse events.
final class SelectionDimView: NSView {
    var selection: NSRect? { didSet { needsDisplay = true } }
    var pixelScale: CGFloat = 1

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.45)
        guard let selection, selection.width > 0, selection.height > 0 else {
            dim.setFill()
            bounds.fill()
            return
        }
        let mask = NSBezierPath(rect: bounds)
        mask.append(NSBezierPath(rect: selection))
        mask.windingRule = .evenOdd
        dim.setFill()
        mask.fill()

        InlineToolbar.accent.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1.5
        border.stroke()

        InlineToolbar.accent.setFill()
        for (_, point) in InlineCanvas.handlePoints(selection) {
            NSBezierPath(ovalIn: NSRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)).fill()
        }

        let label = "\(Int((selection.width * pixelScale).rounded())) × \(Int((selection.height * pixelScale).rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        var origin = NSPoint(x: selection.minX, y: selection.maxY + 6)
        if origin.y + size.height > bounds.maxY { origin.y = selection.maxY - size.height - 6 }
        let background = NSRect(x: origin.x, y: origin.y, width: size.width + 10, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        (label as NSString).draw(at: NSPoint(x: origin.x + 5, y: origin.y + 2), withAttributes: attrs)
    }
}
