import XCTest
@testable import ClipDiffCore

final class FinderComparisonRequestTests: XCTestCase {
    func testRoundTripsExactlyTwoFileURLsInOrder() throws {
        let fileURLs = [
            URL(fileURLWithPath: "/tmp/older file & notes.txt"),
            URL(fileURLWithPath: "/tmp/newer # notes.txt")
        ]
        let request = try XCTUnwrap(FinderComparisonRequest(fileURLs: fileURLs))

        let decoded = try XCTUnwrap(
            FinderComparisonRequest(url: try XCTUnwrap(request.url))
        )

        XCTAssertEqual(decoded.fileURLs, fileURLs)
        XCTAssertEqual(decoded.operation, .compareSelectedFiles)
    }

    func testRoundTripsOneFileOperationWithReservedAndUnicodeCharacters() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/café + 100% & #.txt")
        let request = try XCTUnwrap(FinderComparisonRequest(
            operation: .compareWithCurrent,
            fileURLs: [fileURL]
        ))

        let decoded = try XCTUnwrap(FinderComparisonRequest(url: try XCTUnwrap(request.url)))
        XCTAssertEqual(decoded.operation, .compareWithCurrent)
        XCTAssertEqual(decoded.fileURLs, [fileURL])
    }

    func testRejectsMalformedRequests() {
        XCTAssertNil(FinderComparisonRequest(fileURLs: []))
        XCTAssertNil(FinderComparisonRequest(fileURLs: [
            URL(fileURLWithPath: "/tmp/one.txt")
        ]))
        XCTAssertNil(FinderComparisonRequest(url: URL(string: "https://example.com")!))
        XCTAssertNil(FinderComparisonRequest(
            operation: .compareWithCurrent,
            fileURLs: [URL(fileURLWithPath: "/tmp/one"), URL(fileURLWithPath: "/tmp/two")]
        ))
        XCTAssertNil(FinderComparisonRequest(
            url: URL(string: "clipdiff://compare-selected-files?file=https://example.com&file=file:///tmp/two.txt")!
        ))
        XCTAssertNil(FinderComparisonRequest(url: URL(string: "clipdiff://unknown?file=file:///tmp/one")!))
        XCTAssertNil(FinderComparisonRequest(url: URL(string: "clipdiff://compare-with-current")!))
        XCTAssertNil(FinderComparisonRequest(url: URL(string: "clipdiff://compare-with-current?file=file:///tmp/one&extra=x")!))
        XCTAssertNil(FinderComparisonRequest(url: URL(string: "clipdiff://compare-with-current?file=file:///tmp/one&file=file:///tmp/two")!))
    }
}
