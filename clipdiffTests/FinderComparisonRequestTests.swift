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
    }

    func testRejectsMalformedRequests() {
        XCTAssertNil(FinderComparisonRequest(fileURLs: []))
        XCTAssertNil(FinderComparisonRequest(fileURLs: [
            URL(fileURLWithPath: "/tmp/one.txt")
        ]))
        XCTAssertNil(FinderComparisonRequest(url: URL(string: "https://example.com")!))
        XCTAssertNil(FinderComparisonRequest(
            url: URL(string: "clipdiff://compare-selected-files?file=https://example.com&file=file:///tmp/two.txt")!
        ))
    }
}
