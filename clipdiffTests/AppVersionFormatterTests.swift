import XCTest
@testable import ClipDiffCore

final class AppVersionFormatterTests: XCTestCase {
    func testTaggedReleaseShowsTagInsteadOfCommit() {
        XCTAssertEqual(
            AppVersionFormatter.aboutVersion(
                releaseTag: "v0.9.321",
                commit: "753aab75f36e959cf8dfa6d72a2175110c9ed608"
            ),
            "0.9.321"
        )
    }

    func testPrereleasePreservesSuffixWithoutCommit() {
        XCTAssertEqual(
            AppVersionFormatter.aboutVersion(releaseTag: "v1.0.0-rc.1", commit: nil),
            "1.0.0-rc.1"
        )
    }

    func testReleaseVersionWithoutTagPrefixIsUnchanged() {
        XCTAssertEqual(
            AppVersionFormatter.aboutVersion(releaseTag: "0.9.321", commit: nil),
            "0.9.321"
        )
    }

    func testUntaggedBuildShowsEightCharacterCommit() {
        let tags: [String?] = [nil, "", " \n\t"]
        for tag in tags {
            XCTAssertEqual(
                AppVersionFormatter.aboutVersion(
                    releaseTag: tag,
                    commit: "abcdef0123456789"
                ),
                "abcdef01"
            )
        }
    }

    func testBuildMetadataTrimsWhitespace() {
        XCTAssertEqual(
            AppVersionFormatter.aboutVersion(releaseTag: " v0.9.0\n", commit: nil),
            "0.9.0"
        )
        XCTAssertEqual(
            AppVersionFormatter.aboutVersion(releaseTag: nil, commit: " ABCDEF0123456789\n"),
            "ABCDEF01"
        )
    }

    func testUntaggedBuildWithMissingOrInvalidCommitShowsUnavailable() {
        let commits: [String?] = [nil, "", "preview", "abcdef", "$(GIT_COMMIT)"]
        for commit in commits {
            XCTAssertEqual(
                AppVersionFormatter.aboutVersion(releaseTag: nil, commit: commit),
                "Unavailable"
            )
        }
    }
}
