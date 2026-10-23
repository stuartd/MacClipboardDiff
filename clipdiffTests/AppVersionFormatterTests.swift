import XCTest
@testable import ClipDiffCore

final class AppVersionFormatterTests: XCTestCase {
    func testTaggedReleaseShowsTagInsteadOfCommit() {
        XCTAssertEqual(
            AppVersionFormatter.aboutVersion(
                releaseTag: "v0.9.0",
                commit: "753aab75f36e959cf8dfa6d72a2175110c9ed608"
            ),
            .init(label: "Version", value: "v0.9.0")
        )
    }

    func testPrereleasePreservesFullTagWithoutCommit() {
        XCTAssertEqual(
            AppVersionFormatter.aboutVersion(releaseTag: "v1.0.0-rc.1", commit: nil),
            .init(label: "Version", value: "v1.0.0-rc.1")
        )
    }

    func testUntaggedBuildShowsShortCommit() {
        let tags: [String?] = [nil, "", " \n\t"]
        for tag in tags {
            XCTAssertEqual(
                AppVersionFormatter.aboutVersion(
                    releaseTag: tag,
                    commit: "abcdef0123456789"
                ),
                .init(label: "Commit", value: "abcdef0")
            )
        }
    }

    func testBuildMetadataTrimsWhitespace() {
        XCTAssertEqual(
            AppVersionFormatter.aboutVersion(releaseTag: " v0.9.0\n", commit: nil),
            .init(label: "Version", value: "v0.9.0")
        )
        XCTAssertEqual(
            AppVersionFormatter.aboutVersion(releaseTag: nil, commit: " ABCDEF0123456789\n"),
            .init(label: "Commit", value: "ABCDEF0")
        )
    }

    func testUntaggedBuildWithMissingOrInvalidCommitShowsUnavailable() {
        let commits: [String?] = [nil, "", "preview", "abcdef", "$(GIT_COMMIT)"]
        for commit in commits {
            XCTAssertEqual(
                AppVersionFormatter.aboutVersion(releaseTag: nil, commit: commit),
                .init(label: "Commit", value: "Unavailable")
            )
        }
    }
}
