import AppKit

protocol ClipboardTextStore: AnyObject {
    var changeCount: Int { get }
    var text: String? { get }

    func replaceText(_ text: String)
}

final class SystemClipboardTextStore: ClipboardTextStore {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    var text: String? {
        guard pasteboard.availableType(from: [.string]) != nil else {
            return nil
        }

        return pasteboard.string(forType: .string)
    }

    func replaceText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
