import Cocoa

// Renders the app icon (purple squircle, dashed selection, red arrow) at 1024 px.
// Usage: swift scripts/make-icon.swift <out.png>, then scripts/make-icon.sh builds AppIcon.icns from it.
let outFile = URL(fileURLWithPath: CommandLine.arguments[1])
let size: CGFloat = 1024
let accent = NSColor(srgbRed: 0.45, green: 0.0, blue: 0.59, alpha: 1)
let accentLight = NSColor(srgbRed: 0.64, green: 0.22, blue: 0.86, alpha: 1)
let red = NSColor(srgbRed: 1, green: 0.02, blue: 0, alpha: 1)

/// macOS icon grid: 824 pt squircle centered in 1024 with a soft shadow.
func squircle(_ ctx: CGContext, fill: (CGRect) -> Void) {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    fill(rect)
    ctx.restoreGState()
}

func gradient(_ ctx: CGContext, _ rect: CGRect, _ top: NSColor, _ bottom: NSColor) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bottom.cgColor, top.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
}

func marquee(_ ctx: CGContext, _ r: CGRect, color: NSColor, dashed: Bool, width: CGFloat) {
    ctx.saveGState()
    ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width)
    if dashed { ctx.setLineDash(phase: 0, lengths: [42, 26]) }
    ctx.stroke(r)
    ctx.restoreGState()
    ctx.setFillColor(color.cgColor)
    for p in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
        ctx.fillEllipse(in: CGRect(x: p.x - 26, y: p.y - 26, width: 52, height: 52))
    }
}

func arrow(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, color: NSColor, width: CGFloat) {
    let angle = atan2(b.y - a.y, b.x - a.x)
    let head: CGFloat = width * 3.2
    let base = CGPoint(x: b.x - head * 0.8 * cos(angle), y: b.y - head * 0.8 * sin(angle))
    ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width); ctx.setLineCap(.round)
    ctx.move(to: a); ctx.addLine(to: base); ctx.strokePath()
    ctx.setFillColor(color.cgColor)
    ctx.move(to: b)
    ctx.addLine(to: CGPoint(x: b.x - head * cos(angle - .pi / 6), y: b.y - head * sin(angle - .pi / 6)))
    ctx.addLine(to: CGPoint(x: b.x - head * cos(angle + .pi / 6), y: b.y - head * sin(angle + .pi / 6)))
    ctx.closePath(); ctx.fillPath()
}

func render(_ name: String, _ draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: outFile)
}

render("AppIcon.png") { ctx in
    squircle(ctx) { r in gradient(ctx, r, accentLight, accent) }
    marquee(ctx, CGRect(x: 300, y: 330, width: 430, height: 340), color: .white, dashed: true, width: 22)
    arrow(ctx, from: CGPoint(x: 250, y: 220), to: CGPoint(x: 560, y: 470), color: red, width: 46)
}
