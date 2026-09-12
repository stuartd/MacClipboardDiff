import Foundation

#if canImport(AppKit)
import AppKit
#endif

private enum ClipboardPrivacyMarker {
    // These de facto pasteboard types are used by password managers and other
    // privacy-conscious producers. Inspect their names before asking AppKit to
    // materialize either file URLs or string data.
    static let concealed = "org.nspasteboard.ConcealedType"
    static let transient = "org.nspasteboard.TransientType"

    static func excludesCapture(_ typeIdentifiers: [String]) -> Bool {
        typeIdentifiers.contains(concealed) || typeIdentifiers.contains(transient)
    }
}

protocol ClipboardPasteboard: AnyObject {
    var changeCount: Int { get }
    var clipboardTypeIdentifiers: [String] { get }

    func readClipboardFileURLs() -> [URL]
    func readClipboardString() -> String?
    func clearClipboardContents()
    func writeClipboardString(_ text: String)
}

#if canImport(AppKit)
extension NSPasteboard: ClipboardPasteboard {
    var clipboardTypeIdentifiers: [String] {
        types?.map(\.rawValue) ?? []
    }

    func readClipboardFileURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        return readObjects(forClasses: [NSURL.self], options: options)?
            .compactMap { object -> URL? in
                guard let url = object as? NSURL else { return nil }
                let value = url as URL
                return value.isFileURL ? value : nil
            } ?? []
    }

    func readClipboardString() -> String? {
        guard availableType(from: [.string]) != nil else { return nil }
        return string(forType: .string)
    }

    func clearClipboardContents() {
        _ = clearContents()
    }

    func writeClipboardString(_ text: String) {
        _ = setString(text, forType: .string)
    }
}
#endif

protocol ClipboardStore: AnyObject {
    var changeCount: Int { get }

    func readSnapshot() -> ClipboardSnapshot
    func replaceText(_ text: String)
}

final class SystemClipboardStore: ClipboardStore {
    private let pasteboard: ClipboardPasteboard

    init(pasteboard: ClipboardPasteboard) {
        self.pasteboard = pasteboard
    }

#if canImport(AppKit)
    convenience init() {
        self.init(pasteboard: NSPasteboard.general)
    }
#endif

    var changeCount: Int {
        pasteboard.changeCount
    }

    func readSnapshot() -> ClipboardSnapshot {
        let typeIdentifiers = pasteboard.clipboardTypeIdentifiers
        guard !ClipboardPrivacyMarker.excludesCapture(typeIdentifiers) else {
            return .nonText
        }

        let fileURLs = pasteboard.readClipboardFileURLs()

        if !fileURLs.isEmpty {
            return .fileURLs(fileURLs)
        }

        if let text = pasteboard.readClipboardString() {
            return text.isEmpty ? .explicitClear : .text(text)
        }

        if typeIdentifiers.isEmpty {
            return .explicitClear
        }

        return .nonText
    }

    func replaceText(_ text: String) {
        pasteboard.clearClipboardContents()
        pasteboard.writeClipboardString(text)
    }
}
