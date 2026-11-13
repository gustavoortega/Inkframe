import XCTest
@testable import ScreenCap

final class SaveScreenshotTests: XCTestCase {
    /// Screenshots can hold secrets: the saved file must be owner-only and must never replace an existing file.
    func testWritesOwnerOnlyFileAndNeverOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try InlineCaptureSession.writeExclusive(Data("first".utf8), in: dir, now: now)
        let second = try InlineCaptureSession.writeExclusive(Data("second".utf8), in: dir, now: now)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
        for url in [first, second] {
            let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(mode?.int16Value, 0o600, url.lastPathComponent)
        }
    }
}
