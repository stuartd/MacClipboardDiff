import XCTest
@testable import ClipDiffCore

final class FinderSingleFileRequestStateTests: XCTestCase {
    func testActiveCompletionConsumesOnlyMatchingEntryAndMonitoringState() {
        var state = FinderSingleFileRequestState()
        let entryID = UUID()
        let token = state.begin(currentEntryID: entryID, pasteboardChangeCount: 4, isMonitoring: true)

        XCTAssertTrue(state.consumeIfValid(
            token, currentEntryID: entryID, pasteboardChangeCount: 4, isMonitoring: true
        ))
        XCTAssertNil(state.activeToken)
    }

    func testClearCopyOrTransitionCancellationPreventsLateCompletion() {
        for _ in 0..<3 {
            var state = FinderSingleFileRequestState()
            let id = UUID()
            let token = state.begin(currentEntryID: id, pasteboardChangeCount: 1, isMonitoring: true)
            state.cancel()
            XCTAssertFalse(state.consumeIfValid(
                token, currentEntryID: id, pasteboardChangeCount: 1, isMonitoring: true
            ))
        }
    }

    func testNewCaptureIncludingIdenticalTextIsDetectedByIdentity() {
        var state = FinderSingleFileRequestState()
        let token = state.begin(currentEntryID: UUID(), pasteboardChangeCount: 1, isMonitoring: true)

        XCTAssertFalse(state.consumeIfValid(
            token, currentEntryID: UUID(), pasteboardChangeCount: 1, isMonitoring: true
        ))
    }

    func testNewFinderRequestSupersedesOldGeneration() {
        var state = FinderSingleFileRequestState()
        let id = UUID()
        let old = state.begin(currentEntryID: id, pasteboardChangeCount: 1, isMonitoring: true)
        _ = state.begin(currentEntryID: id, pasteboardChangeCount: 1, isMonitoring: true)

        XCTAssertFalse(state.consumeIfValid(
            old, currentEntryID: id, pasteboardChangeCount: 1, isMonitoring: true
        ))
    }

    func testUnobservedOrIgnoredClipboardChangeInvalidatesWhileMonitoring() {
        var state = FinderSingleFileRequestState()
        let id = UUID()
        let token = state.begin(currentEntryID: id, pasteboardChangeCount: 8, isMonitoring: true)

        XCTAssertFalse(state.consumeIfValid(
            token, currentEntryID: id, pasteboardChangeCount: 9, isMonitoring: true
        ))
    }

    func testClipboardChangeIsAllowedWhileMonitoringRemainsPaused() {
        var state = FinderSingleFileRequestState()
        let id = UUID()
        let token = state.begin(currentEntryID: id, pasteboardChangeCount: 8, isMonitoring: false)

        XCTAssertTrue(state.consumeIfValid(
            token, currentEntryID: id, pasteboardChangeCount: 99, isMonitoring: false
        ))
    }
}
