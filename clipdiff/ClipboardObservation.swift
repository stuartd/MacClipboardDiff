import Foundation

struct CapturedClipboardValue: Equatable, Sendable {
    let text: String
    let sourceFileName: String?
    let sourceFilePath: String?

    init(
        text: String,
        sourceFileName: String? = nil,
        sourceFilePath: String? = nil
    ) {
        self.text = text
        self.sourceFileName = sourceFileName
        self.sourceFilePath = sourceFilePath
    }
}

enum ClipboardSnapshot: Equatable, Sendable {
    case text(String)
    case fileURLs([URL])
    case explicitClear
    case nonText
}

enum ClipboardObservationContent: Equatable, Sendable {
    case value(CapturedClipboardValue)
    case pair(previous: CapturedClipboardValue, current: CapturedClipboardValue)
    case explicitClear
    case nonText
    case ownWrite
}

struct ClipboardObservation: Equatable, Sendable {
    let changeCount: Int
    let observedAt: Date
    let content: ClipboardObservationContent
}

enum ClipboardHistoryChange: Equatable {
    case none
    case accepted
    case removedByRecentClear
}
