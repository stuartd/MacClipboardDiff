import XCTest
@testable import ClipDiffCore

final class FinderCaptureIdentityTests: XCTestCase {
    private let path = "/files/old/settings.json"
    private let sessionID = UUID()

    func testMatchesTheSameStandardizedPath() {
        let identity = makeIdentity(path)

        for selectedPath in [path, "/files/old/./settings.json", "/files/new/../old/settings.json"] {
            let url = URL(fileURLWithPath: selectedPath)
            XCTAssertTrue(identity.matches(url))
            XCTAssertTrue(FinderCaptureIdentity.isSamePath(url, sourceFilePath: path))
        }
    }

    func testSameBasenameInAnotherDirectoryRemainsComparable() {
        let other = URL(fileURLWithPath: "/files/new/settings.json")
        XCTAssertFalse(makeIdentity(path).matches(other))
        XCTAssertFalse(FinderCaptureIdentity.isSamePath(other, sourceFilePath: path))
    }

    func testPlainTextCaptureDoesNotFilterAnyFile() {
        let selected = URL(fileURLWithPath: path)
        XCTAssertFalse(makeIdentity(nil).matches(selected))
        XCTAssertFalse(FinderCaptureIdentity.isSamePath(selected, sourceFilePath: nil))
    }

    func testCaptureFromBeforeANewPathnameCopyDoesNotHideTheTarget() {
        let target = URL(fileURLWithPath: path)
        let oldCapture = makeIdentity(path, pasteboardChangeCount: 4)
        XCTAssertTrue(oldCapture.matches(target, pasteboardChangeCount: 4))
        XCTAssertFalse(oldCapture.matches(target, pasteboardChangeCount: 5))
    }

    func testCompletedPathnameCaptureFiltersOnlyItsOwnFile() {
        let copiedPath = "/files/new/settings.json"
        let newCapture = makeIdentity(copiedPath, pasteboardChangeCount: 5)
        XCTAssertFalse(newCapture.matches(URL(fileURLWithPath: path), pasteboardChangeCount: 5))
        XCTAssertTrue(newCapture.matches(URL(fileURLWithPath: copiedPath), pasteboardChangeCount: 5))
    }

    func testMatchesCanonicalUnicodePathSpellings() {
        let identity = makeIdentity("/files/caf\u{00e9}.txt")
        XCTAssertTrue(identity.matches(URL(fileURLWithPath: "/files/cafe\u{0301}.txt")))
    }

    func testNotificationRoundTripIncludesNoSourcePathOrFilename() throws {
        for path: String? in [self.path, nil] {
            let identity = makeIdentity(path)
            let object = try XCTUnwrap(identity.notificationObject)
            XCTAssertEqual(FinderCaptureIdentity(notificationObject: object), identity)
            XCTAssertFalse(object.contains("settings.json"))
            XCTAssertFalse(object.contains("/files"))
        }
    }

    func testFingerprintsChangeBetweenAppSessions() {
        let first = makeIdentity(path)
        let second = makeIdentity(path, sessionID: UUID())
        XCTAssertNotEqual(first.notificationObject, second.notificationObject)
        XCTAssertTrue(first.matches(URL(fileURLWithPath: path)))
        XCTAssertTrue(second.matches(URL(fileURLWithPath: path)))
    }

    func testMalformedNotificationsAreIgnored() throws {
        for object: Any? in [nil, 4, "", "{}", "not json"] {
            XCTAssertNil(FinderCaptureIdentity(notificationObject: object))
        }
        let data = try XCTUnwrap(makeIdentity(path).notificationObject?.data(using: .utf8))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["pathFingerprint"] = path
        XCTAssertNil(FinderCaptureIdentity(notificationObject: String(
            data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8
        )))
    }

    func testInvalidSourcePathsAndNonFileURLsNeverMatch() {
        XCTAssertFalse(makeIdentity("settings.json").matches(URL(fileURLWithPath: path)))
        XCTAssertFalse(makeIdentity(path).matches(URL(string: "https://example.com/settings.json")!))
    }

    private func makeIdentity(
        _ path: String?,
        sessionID: UUID? = nil,
        pasteboardChangeCount: Int = 0
    ) -> FinderCaptureIdentity {
        FinderCaptureIdentity(
            sourceFilePath: path,
            processIdentifier: 123,
            sessionID: sessionID ?? self.sessionID,
            revision: 1,
            pasteboardChangeCount: pasteboardChangeCount
        )
    }
}
