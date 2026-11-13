import Cocoa

/// Round-button toolbar shown under the selection during in-place capture (flameshot layout).
final class InlineToolbar: NSView {
    enum Action {
        case tool(AnnotationToolType, filled: Bool)
        case color
        case undo, redo, copy, save, pin, close
    }

    private struct Item {
        let action: Action
        let symbol: String
        let tip: String
    }

    static let accent = NSColor(srgbRed: 0.45, green: 0.0, blue: 0.59, alpha: 1)
    private static let buttonSize: CGFloat = 32
    private static let spacing: CGFloat = 6

    private let items: [Item] = [
        Item(action: .tool(.freehand, filled: false), symbol: "pencil", tip: "Pencil"),
        Item(action: .tool(.line, filled: false), symbol: "line.diagonal", tip: "Line"),
        Item(action: .tool(.arrow, filled: false), symbol: "arrow.down.left", tip: "Arrow"),
        Item(action: .tool(.rectangle, filled: false), symbol: "rectangle", tip: "Rectangle"),
        Item(action: .tool(.rectangle, filled: true), symbol: "rectangle.fill", tip: "Filled rectangle"),
        Item(action: .tool(.ellipse, filled: false), symbol: "circle", tip: "Ellipse"),
        Item(action: .tool(.highlight, filled: false), symbol: "highlighter", tip: "Marker"),
        Item(action: .tool(.text, filled: false), symbol: "textformat", tip: "Text"),
        Item(action: .tool(.numberedStep, filled: false), symbol: "1.circle", tip: "Counter"),
        Item(action: .tool(.blur, filled: false), symbol: "checkerboard.rectangle", tip: "Pixelate"),
        Item(action: .tool(.select, filled: false), symbol: "arrow.up.and.down.and.arrow.left.and.right", tip: "Move annotation or selection"),
        Item(action: .color, symbol: "circle.fill", tip: "Color and size (or right-click a tool)"),
        Item(action: .undo, symbol: "arrow.uturn.backward", tip: "Undo (Cmd+Z)"),
        Item(action: .redo, symbol: "arrow.uturn.forward", tip: "Redo (Cmd+Shift+Z)"),
        Item(action: .copy, symbol: "doc.on.doc", tip: "Copy (Cmd+C)"),
        Item(action: .save, symbol: "square.and.arrow.down", tip: "Save (Cmd+S)"),
        Item(action: .close, symbol: "xmark", tip: "Close (Esc)"),
        Item(action: .pin, symbol: "pin.fill", tip: "Pin"),
    ]

    var onAction: ((Action) -> Void)?
    /// Tip of the hovered button and its frame in toolbar coordinates; nil when the pointer leaves.
    /// The overlay draws its own label because system tooltips render below a screen-saver-level window.
    var onHover: ((String, NSRect)?) -> Void = { _ in }
    /// Right-click on a tool, or click on the color button: open that tool's color and size settings.
    var onSettings: ((Action, NSRect) -> Void)?
    private var buttons: [ToolbarButton] = []
    private var colorButton: NSButton?

    init() {
        let count = CGFloat(items.count)
        let width = count * Self.buttonSize + (count - 1) * Self.spacing
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.buttonSize))
        wantsLayer = true
        for (index, item) in items.enumerated() {
            let button = makeButton(item: item, index: index)
            button.frame.origin.x = CGFloat(index) * (Self.buttonSize + Self.spacing)
            addSubview(button)
            buttons.append(button)
            if case .color = item.action { colorButton = button }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func makeButton(item: Item, index: Int) -> ToolbarButton {
        let button = ToolbarButton(frame: NSRect(x: 0, y: 0, width: Self.buttonSize, height: Self.buttonSize))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = Self.buttonSize / 2
        button.contentTintColor = .white
        button.onRightClick = { [weak self, weak button] in
            guard let self, let button else { return }
            switch item.action {
            case .tool, .color: self.onSettings?(item.action, button.frame)
            default: break
            }
        }
        button.onHover = { [weak self, weak button] inside in
            guard let self, let button else { return }
            self.onHover(inside ? (item.tip, button.frame) : nil)
        }
        button.tag = index
        button.target = self
        button.action = #selector(buttonPressed(_:))
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.tip)?
            .withSymbolConfiguration(config) {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = String(item.tip.prefix(1))
        }
        return button
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        onAction?(items[sender.tag].action)
    }

    /// Highlights the active tool with a white ring.
    func setActiveTool(_ tool: AnnotationToolType, filled: Bool) {
        for (index, item) in items.enumerated() {
            var active = false
            if case .tool(let t, let f) = item.action { active = (t == tool && f == filled) }
            buttons[index].isActive = active
        }
    }

    func setColor(_ color: NSColor) {
        colorButton?.contentTintColor = color
    }

    var colorButtonFrame: NSRect { colorButton?.frame ?? .zero }

    /// Below the selection, else above it, else inside its bottom edge; always clamped to the screen.
    func position(for selection: NSRect, in bounds: NSRect) {
        let margin: CGFloat = 8
        var x = selection.midX - frame.width / 2
        x = min(max(x, margin), bounds.maxX - frame.width - margin)
        var y = selection.minY - frame.height - 10
        if y < margin {
            y = selection.maxY + 10
            if y + frame.height > bounds.maxY - margin {
                y = selection.minY + 10
            }
        }
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Round toolbar button: lighter fill and a thin ring on hover, thick ring when it is the active tool.
private final class ToolbarButton: NSButton {
    var onHover: ((Bool) -> Void)?
    var onRightClick: (() -> Void)?
    var isActive = false { didSet { refresh() } }
    private var isHovered = false { didSet { refresh() } }
    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHover?(false)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func refresh() {
        let fill = isHovered ? InlineToolbar.accent.blended(withFraction: 0.35, of: .white) ?? InlineToolbar.accent : InlineToolbar.accent
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = NSColor.white.cgColor
        layer?.borderWidth = isActive ? 2 : (isHovered ? 1 : 0)
    }
}
