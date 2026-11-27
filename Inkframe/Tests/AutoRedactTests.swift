import XCTest
import CoreText
@testable import Inkframe

final class AutoRedactTests: XCTestCase {
    /// Runs real Vision on a rendered selection: the key line gets a rect over the token, the plain line none,
    /// which also pins the normalized-box to canvas-point mapping including the selection origin.
    func testRedactsOnlyTheSecretLineInCanvasPoints() throws {
        let selection = NSRect(x: 300, y: 150, width: 600, height: 100)
        let width = 1200, height = 200
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Menlo" as CFString, 28, nil)
        let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        func line(_ text: String) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): black,
            ]))
        }
        let token = "AKIAZZZZEXAMPLE00000"
        let keyLine = "key \(token)"
        let secret = line(keyLine), plain = line("Instances running")
        context.textPosition = CGPoint(x: 40, y: 130)
        CTLineDraw(secret, context)
        context.textPosition = CGPoint(x: 40, y: 40)
        CTLineDraw(plain, context)
        let image = try XCTUnwrap(context.makeImage())

        // Glyph rects in px, then canvas points. Token y comes from the token alone so "key" adds no descender.
        func canvasRect(_ px: CGRect) -> CGRect {
            CGRect(x: selection.minX + px.minX / 2, y: selection.minY + px.minY / 2,
                   width: px.width / 2, height: px.height / 2)
        }
        // Image bounds are relative to the context text position, so measure from the origin.
        context.textPosition = .zero
        let tokenStart = CTLineGetOffsetForStringIndex(secret, 4, nil)
        let tokenBounds = CTLineGetImageBounds(line(token), context)
        let tokenRect = canvasRect(CGRect(x: 40 + tokenStart, y: 130 + tokenBounds.minY,
                                          width: tokenBounds.width, height: tokenBounds.height))
        let plainBounds = CTLineGetImageBounds(plain, context)
        let plainRect = canvasRect(plainBounds.offsetBy(dx: 40, dy: 40))

        let rects = try AutoRedact.redactions(in: image, selection: selection)
        XCTAssertGreaterThanOrEqual(rects.count, 1, "no rect for the key line")
        XCTAssertTrue(rects.contains { $0.insetBy(dx: -3, dy: -3).contains(tokenRect) },
                      "no rect covers the token \(tokenRect); got \(rects)")
        XCTAssertFalse(rects.contains { $0.intersects(plainRect) }, "plain line was redacted: \(rects)")
    }
}
