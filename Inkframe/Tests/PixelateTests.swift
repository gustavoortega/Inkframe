import XCTest
@testable import Inkframe

final class PixelateTests: XCTestCase {
    private let width = 400
    private let height = 200

    /// Renders the canvas with one blur annotation over seeded noise and counts distinct colors in `pxRect`.
    private func distinctColors(blur rect: NSRect, in pxRect: (x: Int, y: Int, w: Int, h: Int)) throws -> Int {
        var seed: UInt32 = 12345
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            for c in 0..<3 {
                seed = seed &* 1664525 &+ 1013904223
                pixels[i * 4 + c] = UInt8(truncatingIfNeeded: seed >> 24)
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let base = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))

        let canvas = AnnotationCanvas(frame: NSRect(x: 0, y: 0, width: width, height: height))
        canvas.baseImage = NSImage(cgImage: base, size: NSSize(width: width, height: height))
        let blur = Annotation(toolType: .blur)
        blur.rect = rect
        canvas.annotations = [blur]

        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        canvas.drawAnnotations(in: context)

        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var colors = Set<UInt32>()
        for y in pxRect.y..<(pxRect.y + pxRect.h) {
            for x in pxRect.x..<(pxRect.x + pxRect.w) {
                // A CG bitmap stores y=0 in the last row.
                let o = ((height - 1 - y) * width + x) * 4
                colors.insert(UInt32(data[o]) << 24 | UInt32(data[o + 1]) << 16 | UInt32(data[o + 2]) << 8 | UInt32(data[o + 3]))
            }
        }
        return colors.count
    }

    /// A short, wide box over a text line must collapse to a few blocks, not ~30 cells of readable detail.
    func testShortBoxHasFewBlocks() throws {
        let n = try distinctColors(blur: NSRect(x: 100, y: 100, width: 60, height: 14), in: (100, 100, 60, 14))
        XCTAssertTrue((2...5).contains(n), "distinct colors: \(n)")
    }

    /// The floor must not flatten a big box to one color: 200x200 at block 20 is 100 cells.
    func testLargeBoxStaysBlocky() throws {
        let n = try distinctColors(blur: NSRect(x: 0, y: 0, width: 200, height: 200), in: (0, 0, 200, 200))
        XCTAssertTrue((2...100).contains(n), "distinct colors: \(n)")
    }

    /// A cell overhanging the image edge must still be pixelated; unclamped, the original noise shows through.
    func testEdgeBoxDoesNotLeakOriginalPixels() throws {
        let n = try distinctColors(blur: NSRect(x: 380, y: 0, width: 20, height: 20), in: (380, 0, 20, 20))
        XCTAssertLessThanOrEqual(n, 4, "distinct colors: \(n)")
    }
}
