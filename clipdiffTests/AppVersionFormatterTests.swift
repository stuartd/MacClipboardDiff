import XCTest
@testable import ClipDiffCore

final class AppVersionFormatterTests: XCTestCase {
    func testApplicationVersionIncludesBuildAndShortCommit() {
        XCTAssertEqual(
            AppVersionFormatter.applicationVersion(
                buildNumber: "12",
                commit: "753aab75f36e959cf8dfa6d72a2175110c9ed608"
            ),
            "12 · 753aab7"
        )
    }

    func testApplicationVersionOmitsInvalidCommit() {
        XCTAssertEqual(
            AppVersionFormatter.applicationVersion(buildNumber: "12", commit: "preview"),
            "12"
        )
    }

    func testApplicationVersionHandlesMissingBuildNumber() {
        XCTAssertEqual(
            AppVersionFormatter.applicationVersion(
                buildNumber: nil,
                commit: "abcdef0123456789"
            ),
            "abcdef0"
        )
    }
}
