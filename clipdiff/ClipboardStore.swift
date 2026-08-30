import AppKit

protocol ClipboardStore: AnyObject {
    var changeCount: Int { get }

    func readSnapshot() -> ClipboardSnapshot
    func replaceText(_ text: String)
}

final class SystemClipboardStore: ClipboardStore {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func readSnapshot() -> ClipboardSnapshot {
        let fileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let fileURLs = pasteboard
            .readObjects(forClasses: [NSURL.self], options: fileURLReadingOptions)?
            .compactMap { object -> URL? in
                guard let url = object as? NSURL else { return nil }
                let value = url as URL
                return value.isFileURL ? value : nil
            } ?? []

        if !fileURLs.isEmpty {
            return .fileURLs(fileURLs)
        }

        if pasteboard.availableType(from: [.string]) != nil {
            guard let text = pasteboard.string(forType: .string) else {
                return .nonText
            }
            return text.isEmpty ? .explicitClear : .text(text)
        }

        if pasteboard.types?.isEmpty != false {
            return .explicitClear
        }

        return .nonText
    }

    func replaceText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
