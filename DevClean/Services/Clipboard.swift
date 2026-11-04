import AppKit

protocol ClipboardWriting {
    func copy(_ text: String)
}

struct PasteboardClipboard: ClipboardWriting {
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
