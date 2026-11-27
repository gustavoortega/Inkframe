import XCTest
@testable import Inkframe

final class InlineCanvasKeyTests: XCTestCase {
    /// Tab is the only way to move a capture to another display; a swallowed key leaves the user stuck on the wrong one.
    func testTabRequestsDisplaySwitch() throws {
        let canvas = InlineCanvas(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var requests = 0
        canvas.onSwitchDisplay = { requests += 1 }
        let tab = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
        canvas.keyDown(with: tab)
        XCTAssertEqual(requests, 1)
    }

    /// A selection carried from a bigger display must land inside the smaller one, or copy would crop past the image.
    func testCarriedSelectionIsClampedToTheNewDisplay() {
        let canvas = InlineCanvas(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var changes = 0
        canvas.onSelectionChanged = { changes += 1 }
        canvas.restoreSelection(NSRect(x: 150, y: 50, width: 400, height: 300))
        XCTAssertEqual(canvas.selection, NSRect(x: 150, y: 50, width: 50, height: 50))
        XCTAssertEqual(changes, 1, "toolbar is positioned from this callback")

        canvas.restoreSelection(NSRect(x: 500, y: 500, width: 100, height: 100))
        XCTAssertNil(canvas.selection, "a selection fully off the new display must not survive")
    }
}
