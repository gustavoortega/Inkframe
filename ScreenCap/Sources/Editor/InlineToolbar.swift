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
        Item(action: .color, symbol: "circle.fill", tip: "Color (scroll to change thickness)"),
        Item(action: .undo, symbol: "arrow.uturn.backward", tip: "Undo (Cmd+Z)"),
        Item(action: .redo, symbol: "arrow.uturn.forward", tip: "Redo (Cmd+Shift+Z)"),
        Item(action: .copy, symbol: "doc.on.doc", tip: "Copy (Cmd+C)"),
        Item(action: .save, symbol: "square.and.arrow.down", tip: "Save (Cmd+S)"),
        Item(action: .close, symbol: "xmark", tip: "Close (Esc)"),
        Item(action: .pin, symbol: "pin.fill", tip: "Pin"),
    ]

    var onAction: ((Action) -> Void)?
    private var buttons: [NSButton] = []
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

    private func makeButton(item: Item, index: Int) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: Self.buttonSize, height: Self.buttonSize))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = Self.buttonSize / 2
        button.layer?.backgroundColor = Self.accent.cgColor
        button.contentTintColor = .white
        button.toolTip = item.tip
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
            buttons[index].layer?.borderWidth = active ? 2 : 0
            buttons[index].layer?.borderColor = NSColor.white.cgColor
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
