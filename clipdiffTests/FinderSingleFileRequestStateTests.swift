import XCTest
@testable import ClipDiffCore

final class FinderSingleFileRequestStateTests: XCTestCase {
    func testActiveCompletionConsumesOnlyMatchingEntryAndPasteboardState() {
        var state = FinderSingleFileRequestState()
        let entryID = UUID()
        let token = state.begin(currentEntryID: entryID, pasteboardChangeCount: 4)

        XCTAssertTrue(state.consumeIfValid(
            token, currentEntryID: entryID, pasteboardChangeCount: 4
        ))
        XCTAssertNil(state.activeToken)
        XCTAssertFalse(state.consumeIfValid(
            token, currentEntryID: entryID, pasteboardChangeCount: 4
        ))
    }

    func testCancellationPreventsLateCompletion() {
        var state = FinderSingleFileRequestState()
        let id = UUID()
        let token = state.begin(currentEntryID: id, pasteboardChangeCount: 1)
        state.cancel()
        XCTAssertFalse(state.consumeIfValid(
            token, currentEntryID: id, pasteboardChangeCount: 1
        ))
    }

    func testNewCaptureIncludingIdenticalTextIsDetectedByIdentity() {
        var state = FinderSingleFileRequestState()
        let token = state.begin(currentEntryID: UUID(), pasteboardChangeCount: 1)

        XCTAssertFalse(state.consumeIfValid(
            token, currentEntryID: UUID(), pasteboardChangeCount: 1
        ))
    }

    func testNewFinderRequestSupersedesOldGeneration() {
        var state = FinderSingleFileRequestState()
        let id = UUID()
        let old = state.begin(currentEntryID: id, pasteboardChangeCount: 1)
        let current = state.begin(currentEntryID: id, pasteboardChangeCount: 1)

        XCTAssertFalse(state.consumeIfValid(
            old, currentEntryID: id, pasteboardChangeCount: 1
        ))
        XCTAssertTrue(state.consumeIfValid(
            current, currentEntryID: id, pasteboardChangeCount: 1
        ))
    }

    func testUnobservedOrIgnoredClipboardChangeInvalidatesCompletion() {
        var state = FinderSingleFileRequestState()
        let id = UUID()
        let token = state.begin(currentEntryID: id, pasteboardChangeCount: 8)

        XCTAssertFalse(state.consumeIfValid(
            token, currentEntryID: id, pasteboardChangeCount: 9
        ))
    }
}
