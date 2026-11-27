import XCTest
@testable import Inkframe

final class RedactTests: XCTestCase {
    /// Redact must hide the pixels completely: a translucent or undrawn box would leak the secret underneath.
    func testRedactDragRendersOpaqueBlack() throws {
        let canvas = AnnotationCanvas(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let stripes = try XCTUnwrap(Self.stripedImage(width: 400, height: 200))
        canvas.baseImage = NSImage(cgImage: stripes, size: NSSize(width: 200, height: 100))
        canvas.currentTool = .redact

        canvas.mouseDown(with: Self.mouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 20)))
        canvas.mouseDragged(with: Self.mouseEvent(.leftMouseDragged, at: NSPoint(x: 120, y: 70)))
        canvas.mouseUp(with: Self.mouseEvent(.leftMouseUp, at: NSPoint(x: 120, y: 70)))
        XCTAssertEqual(canvas.annotations.count, 1)

        let context = try XCTUnwrap(CGContext(
            data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 400 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(stripes, in: CGRect(x: 0, y: 0, width: 400, height: 200))
        context.scaleBy(x: 2, y: 2)
        canvas.drawAnnotations(in: context)

        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        // Annotation rect in px is (40,40,200,100); a CG bitmap stores y=0 in the last row.
        var notOpaque = 0
        for y in 42..<138 {
            for x in 42..<238 {
                let offset = ((200 - 1 - y) * 400 + x) * 4
                if [data[offset], data[offset + 1], data[offset + 2], data[offset + 3]] != [0, 0, 0, 255] { notOpaque += 1 }
            }
        }
        XCTAssertEqual(notOpaque, 0, "pixels inside the redact box that are not opaque black")
    }

    /// The capture is cropped to the selection, so a box dragged past its edge must not show outside it on screen.
    func testInlineAnnotationsAreClippedToTheSelection() throws {
        let canvas = InlineCanvas(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        canvas.drawsBaseImage = false
        canvas.mouseDown(with: Self.mouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 20)))
        canvas.mouseDragged(with: Self.mouseEvent(.leftMouseDragged, at: NSPoint(x: 100, y: 80)))
        canvas.mouseUp(with: Self.mouseEvent(.leftMouseUp, at: NSPoint(x: 100, y: 80)))
        XCTAssertEqual(canvas.selection, NSRect(x: 20, y: 20, width: 80, height: 60))

        canvas.currentTool = .redact
        canvas.mouseDown(with: Self.mouseEvent(.leftMouseDown, at: NSPoint(x: 60, y: 40)))
        canvas.mouseDragged(with: Self.mouseEvent(.leftMouseDragged, at: NSPoint(x: 180, y: 60)))
        canvas.mouseUp(with: Self.mouseEvent(.leftMouseUp, at: NSPoint(x: 180, y: 60)))
        XCTAssertEqual(canvas.annotations.count, 1)

        let rep = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        // Bitmap rows count from the top; canvas y 50 is row 50 in a 100-point view at any scale factor.
        func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let scale = CGFloat(rep.pixelsWide) / canvas.bounds.width
            return rep.colorAt(x: Int(x * scale), y: Int((canvas.bounds.height - y) * scale))?.alphaComponent ?? -1
        }
        XCTAssertEqual(alpha(80, 50), 1, "redact missing inside the selection")
        XCTAssertEqual(alpha(150, 50), 0, "redact painted outside the selection")
    }

    private static func stripedImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for x in stride(from: 0, to: width, by: 2) {
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return context.makeImage()
    }

    private static func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }
}
