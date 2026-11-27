import XCTest
@testable import Inkframe

final class SecretDetectorTests: XCTestCase {
    /// One table per outcome: a miss leaks a secret into a shared screenshot, a false hit only costs an undo.
    func testSensitiveLinesAreFlagged() {
        let positives = [
            "AKIAZZZZEXAMPLE00000",
            "AKlAZZZZEXAMPLE00000",  // OCR reads the second "I" as a lowercase L
            "eyJhbGciOiJub25lIn0.e30.x",
            "ghp_" + String(repeating: "x1", count: 15),
            "xoxb-0000-fake",
            "123456789012",
            "1234-5678-9012",
            "10.1.2.3",
            "alice@example.com",
            "password: hunter2",
            "aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bD1fH3jL5nP7r",  // wrapped base64 continuation, 40 chars
        ]
        for line in positives {
            XCTAssertTrue(SecretDetector.isSensitive(line), "should flag: \(line)")
        }
    }

    func testOrdinaryLinesAreNotFlagged() {
        let negatives = [
            "Instances (3)",
            "2026-11-27 03:34",
            "v1.2.3",
            "Hello world",
            "aB3dE5gH7jK9mN1pQ3sT5vW",  // 23 chars, one below the opaque-token floor
            String(repeating: "abcdefgh", count: 3),  // 24 letters, no digit
            "/aws/lambda/my-function-name-2",
            "3f2b1c9e-8d7a-4b6c-9e5f-1a2b3c4d5e6f",
        ]
        for line in negatives {
            XCTAssertFalse(SecretDetector.isSensitive(line), "should not flag: \(line)")
        }
    }
}
