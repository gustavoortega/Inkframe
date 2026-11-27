import AppKit

enum Clipboard {
    /// Host-only: keeps captures off Universal Clipboard, which hands the pasteboard to other devices via iCloud.
    @discardableResult
    static func write(_ objects: [NSPasteboardWriting]) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        return pasteboard.writeObjects(objects)
    }
}
