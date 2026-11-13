import XCTest
@testable import Inkframe

final class ToolSettingsTests: XCTestCase {
    private let keys = ["inlineColorIndex", "inlineLineWidth", "inlineFontSize"]

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    /// Preferences are editable with `defaults write`; out-of-range values must not crash or produce invisible strokes.
    func testLoadClampsTamperedPreferences() {
        UserDefaults.standard.set(99, forKey: "inlineColorIndex")
        UserDefaults.standard.set(-5.0, forKey: "inlineLineWidth")
        UserDefaults.standard.set(Double.infinity, forKey: "inlineFontSize")

        let settings = InlineToolSettings.load()

        XCTAssertEqual(settings.colorIndex, 0)
        XCTAssertEqual(settings.lineWidth, InlineToolSettings.lineWidthRange.lowerBound)
        XCTAssertEqual(settings.fontSize, InlineToolSettings.fontSizeRange.lowerBound)
        XCTAssertEqual(settings.color, InlineToolSettings.palette[0])
    }
}
