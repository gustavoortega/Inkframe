import Cocoa

/// Color, thickness and font size for in-place capture, kept across captures like flameshot does.
struct InlineToolSettings {
    static let palette: [NSColor] = [
        NSColor(srgbRed: 1, green: 0x05 / 255, blue: 0, alpha: 1), .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .black, .white,
    ]
    static let lineWidthRange: ClosedRange<CGFloat> = 1...20
    static let fontSizeRange: ClosedRange<CGFloat> = 10...72

    var colorIndex: Int
    var lineWidth: CGFloat
    var fontSize: CGFloat

    var color: NSColor { Self.palette[colorIndex] }

    private static let store = UserDefaults.standard
    private enum Key {
        static let color = "inlineColorIndex"
        static let lineWidth = "inlineLineWidth"
        static let fontSize = "inlineFontSize"
    }

    /// Stored values are clamped: preferences are user-editable with `defaults write`.
    static func load() -> InlineToolSettings {
        let index = store.object(forKey: Key.color) as? Int ?? 0
        let width = store.object(forKey: Key.lineWidth) as? Double ?? 2
        let font = store.object(forKey: Key.fontSize) as? Double ?? 16
        return InlineToolSettings(
            colorIndex: palette.indices.contains(index) ? index : 0,
            lineWidth: clamp(CGFloat(width), to: lineWidthRange),
            fontSize: clamp(CGFloat(font), to: fontSizeRange)
        )
    }

    func save() {
        Self.store.set(colorIndex, forKey: Key.color)
        Self.store.set(Double(lineWidth), forKey: Key.lineWidth)
        Self.store.set(Double(fontSize), forKey: Key.fontSize)
    }

    static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value.rounded(), range.lowerBound), range.upperBound)
    }
}

/// Swatches plus a thickness slider, or a font-size slider for the text tool.
final class ToolSettingsPanel: NSView {
    var onChange: ((InlineToolSettings) -> Void)?

    private var settings: InlineToolSettings
    private let editsFontSize: Bool
    private var swatches: [NSButton] = []
    private let valueLabel = NSTextField(labelWithString: "")
    private static let swatchSize: CGFloat = 22
    private static let gap: CGFloat = 6

    init(settings: InlineToolSettings, editsFontSize: Bool) {
        self.settings = settings
        self.editsFontSize = editsFontSize
        let count = CGFloat(InlineToolSettings.palette.count)
        let width = count * (Self.swatchSize + Self.gap) + Self.gap
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 70))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.cornerRadius = 8
        buildSwatches()
        buildSlider()
        refreshSwatches()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func buildSwatches() {
        for (index, color) in InlineToolSettings.palette.enumerated() {
            let x = Self.gap + CGFloat(index) * (Self.swatchSize + Self.gap)
            let swatch = NSButton(frame: NSRect(x: x, y: 40, width: Self.swatchSize, height: Self.swatchSize))
            swatch.isBordered = false
            swatch.title = ""
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = color.cgColor
            swatch.layer?.cornerRadius = Self.swatchSize / 2
            swatch.layer?.borderColor = NSColor.white.cgColor
            swatch.tag = index
            swatch.target = self
            swatch.action = #selector(pickColor(_:))
            addSubview(swatch)
            swatches.append(swatch)
        }
    }

    private func buildSlider() {
        let title = NSTextField(labelWithString: editsFontSize ? "Font size" : "Thickness")
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = .white
        title.frame = NSRect(x: Self.gap + 2, y: 10, width: 64, height: 16)
        addSubview(title)

        let range = editsFontSize ? InlineToolSettings.fontSizeRange : InlineToolSettings.lineWidthRange
        let value = editsFontSize ? settings.fontSize : settings.lineWidth
        let slider = NSSlider(value: Double(value), minValue: Double(range.lowerBound), maxValue: Double(range.upperBound),
                              target: self, action: #selector(sliderChanged(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 72, y: 8, width: frame.width - 72 - 40, height: 20)
        addSubview(slider)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .white
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: frame.width - 36, y: 10, width: 28, height: 16)
        valueLabel.stringValue = "\(Int(value))"
        addSubview(valueLabel)
    }

    private func refreshSwatches() {
        for swatch in swatches {
            swatch.layer?.borderWidth = swatch.tag == settings.colorIndex ? 2.5 : 0.5
        }
    }

    @objc private func pickColor(_ sender: NSButton) {
        guard InlineToolSettings.palette.indices.contains(sender.tag) else { return }
        settings.colorIndex = sender.tag
        refreshSwatches()
        onChange?(settings)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let range = editsFontSize ? InlineToolSettings.fontSizeRange : InlineToolSettings.lineWidthRange
        let value = InlineToolSettings.clamp(CGFloat(sender.doubleValue), to: range)
        if editsFontSize { settings.fontSize = value } else { settings.lineWidth = value }
        valueLabel.stringValue = "\(Int(value))"
        onChange?(settings)
    }
}
