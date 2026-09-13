import Foundation

/// Small, testable guard for asynchronous Finder reads. Cancellation remains an
/// optimization; every completion must also pass these identity/state checks.
struct FinderSingleFileRequestState {
    struct Token: Equatable {
        fileprivate let generation: UUID
        let expectedCurrentEntryID: UUID
        let pasteboardChangeCount: Int
        let wasMonitoring: Bool
    }

    private(set) var activeToken: Token?

    mutating func begin(
        currentEntryID: UUID,
        pasteboardChangeCount: Int,
        isMonitoring: Bool
    ) -> Token {
        let token = Token(
            generation: UUID(),
            expectedCurrentEntryID: currentEntryID,
            pasteboardChangeCount: pasteboardChangeCount,
            wasMonitoring: isMonitoring
        )
        activeToken = token
        return token
    }

    mutating func cancel() {
        activeToken = nil
    }

    mutating func consumeIfValid(
        _ token: Token,
        currentEntryID: UUID?,
        pasteboardChangeCount: Int,
        isMonitoring: Bool
    ) -> Bool {
        guard activeToken == token else { return false }
        activeToken = nil
        guard currentEntryID == token.expectedCurrentEntryID,
              isMonitoring == token.wasMonitoring,
              (!isMonitoring || pasteboardChangeCount == token.pasteboardChangeCount) else {
            return false
        }
        return true
    }
}
