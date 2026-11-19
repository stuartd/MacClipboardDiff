import Foundation
import XCTest
@testable import ClipDiffCore

final class DiagnosticLogFileTests: XCTestCase {
    func testViewerReadsEventsAcrossLaunchesAndRefreshes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = DiagnosticLogFile(directory: directory)
        let empty = try await first.read()
        XCTAssertEqual(empty, "")
        first.append("[App] ClipDiff started")
        first.append("[App] ClipDiff stopped")
        first.flush()

        let relaunched = DiagnosticLogFile(directory: directory)
        relaunched.append("[Updates] GitHub HTTP status=200")
        let text = try await relaunched.read()
        XCTAssertEqual(text.split(separator: "\n").count, 3)
        XCTAssertTrue(text.contains("[App] ClipDiff started"))
        XCTAssertTrue(text.contains("[App] ClipDiff stopped"))
        XCTAssertTrue(text.contains("[Updates] GitHub HTTP status=200"))
    }

    func testViewerReadsCurrentAndPreviousFilesInOrderAndDropsOlderEvents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticLogFile(directory: directory, maximumBytes: 50)
        log.append("old event".padding(toLength: 20, withPad: "-", startingAt: 0))
        log.append("previous event".padding(toLength: 20, withPad: "-", startingAt: 0))
        log.append("current event".padding(toLength: 20, withPad: "-", startingAt: 0))
        let text = try await log.read()
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.first?.contains("previous event") == true)
        XCTAssertTrue(lines.last?.contains("current event") == true)
    }
}
