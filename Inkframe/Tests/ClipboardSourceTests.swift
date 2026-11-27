import XCTest

/// Guards the contract "a capture never leaves this Mac via the clipboard". The pasteboard write is
/// unobservable at runtime, so this scans for Apple API names that would bypass `Clipboard.write`.
final class ClipboardSourceTests: XCTestCase {
    private let forbidden = [
        #"NSPasteboard\.general"#,
        #"NSPasteboard\("#,
        #":\s*NSPasteboard(?![A-Za-z.])"#,
        #"=\s*\.general\b"#,
        #"clearContents\("#,
        #"declareTypes\("#,
    ]

    func testNoPasteboardWriteBypassesHostOnlyClipboard() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }

        let names = files.map { $0.lastPathComponent }
        XCTAssertGreaterThanOrEqual(files.count, 25)
        XCTAssertTrue(files.contains { $0.path.hasSuffix("Utilities/Clipboard.swift") })
        XCTAssertTrue(files.contains { $0.path.hasSuffix("Capture/InlineCapture.swift") }, "scanned: \(names)")

        let regexes = try forbidden.map { try NSRegularExpression(pattern: $0) }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            if file.path.hasSuffix("Utilities/Clipboard.swift") {
                XCTAssertTrue(text.contains("prepareForNewContents(with: .currentHostOnly)"))
                XCTAssertFalse(text.contains("clearContents("))
                continue
            }
            for regex in regexes where regex.firstMatch(in: text, range: range) != nil {
                XCTFail("\(file.lastPathComponent) matches \(regex.pattern); route it through Clipboard.write")
            }
        }
    }
}
