import Foundation
import XCTest
@testable import ClipDiffCore

final class UpdateCheckerTests: XCTestCase {
    func testReleaseVersionsUseSemanticPrecedence() throws {
        let orderedTags = [
            "v0.9.9", "v0.9.10-rc.2", "v0.9.10-rc.10", "v0.9.10", "v1.0.0"
        ]
        let versions = try orderedTags.map { try XCTUnwrap(ReleaseVersion(tag: $0)) }
        for (older, newer) in zip(versions, versions.dropFirst()) {
            XCTAssertTrue(newer.isNewer(than: older))
            XCTAssertFalse(older.isNewer(than: newer))
        }
        let rebuilt = try XCTUnwrap(ReleaseVersion(tag: "v1.0.0+rebuilt"))
        let original = try XCTUnwrap(versions.last)
        XCTAssertFalse(rebuilt.isNewer(than: original))
        XCTAssertFalse(original.isNewer(than: rebuilt))
        for invalid in ["v0.09.1", "v0.9.1-01", "v0.9", "a1b2c3d4", "v0.9.1\n"] {
            XCTAssertNil(ReleaseVersion(tag: invalid))
        }
    }

    func testReleaseVersionsOrderSameDayRevisionsNumerically() throws {
        let orderedTags = [
            "v0.9.1120", "v0.9.1120.2-rc.1", "v0.9.1120.2", "v0.9.1120.10", "v0.9.1121"
        ]
        let versions = try orderedTags.map { try XCTUnwrap(ReleaseVersion(tag: $0)) }
        for (older, newer) in zip(versions, versions.dropFirst()) {
            XCTAssertTrue(newer.isNewer(than: older))
            XCTAssertFalse(older.isNewer(than: newer))
        }
        XCTAssertNil(ReleaseVersion(tag: "v0.9.1120.02"))
        XCTAssertNil(ReleaseVersion(tag: "v0.9.1120.2.1"))
    }

    func testGitHubReleaseRequiresAStableTagAndUsesTheKnownRepositoryForLinks() throws {
        let payload = Data(#"{"tag_name":"v0.9.1120.2","draft":false,"prerelease":false,"html_url":"https://example.com/"}"#.utf8)
        let version = try GitHubReleaseClient.decodeRelease(payload)
        XCTAssertEqual(version.tag, "v0.9.1120.2")
        XCTAssertEqual(
            GitHubReleaseClient.releasePage(for: version).absoluteString,
            "https://github.com/stuartd/MacClipboardDiff/releases/tag/v0.9.1120.2"
        )
        for payload in [
            #"{"tag_name":"v0.9.1114","draft":true,"prerelease":false}"#,
            #"{"tag_name":"v0.9.1114-rc.1","draft":false,"prerelease":true}"#,
            #"{"tag_name":"unexpected","draft":false,"prerelease":false}"#,
            #"{"tag_name":"v0.9.1114"}"#
        ] {
            XCTAssertThrowsError(try GitHubReleaseClient.decodeRelease(Data(payload.utf8)))
        }
    }

    @MainActor
    func testManualCheckWorksWithoutConsentAndRemembersNewRelease() async {
        let defaults = MemoryDefaults()
        let checker = UpdateChecker(releaseTag: "v0.9.1120.2", defaults: defaults) {
            ReleaseVersion(tag: "v0.9.1120.10")!
        }

        guard case .skipped = await checker.check(manual: false) else {
            return XCTFail("Expected automatic checks to be off before consent")
        }
        XCTAssertNil(checker.availableVersion)
        guard case .available(let version) = await checker.check(manual: true) else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(version.tag, "v0.9.1120.10")
        XCTAssertNil(checker.automaticPreference)

        let relaunched = UpdateChecker(releaseTag: "v0.9.1120.2", defaults: defaults)
        let upgraded = UpdateChecker(releaseTag: "v0.9.1120.10", defaults: defaults)
        XCTAssertEqual(relaunched.availableVersion?.tag, "v0.9.1120.10")
        XCTAssertNil(upgraded.availableVersion)
    }

    @MainActor
    func testLaterOffersTheCachedUpgradeNextLaunch() async throws {
        let defaults = MemoryDefaults()
        let checker = UpdateChecker(releaseTag: "v0.9.1120", defaults: defaults) {
            ReleaseVersion(tag: "v0.9.1121")!
        }

        _ = await checker.check(manual: true)
        let version = try XCTUnwrap(checker.upgradeToOffer)
        checker.markUpgradeOffered(version)
        checker.deferUpgrade(version)
        XCTAssertNil(checker.upgradeToOffer)

        _ = await checker.check(manual: true)
        XCTAssertNil(checker.upgradeToOffer)
        XCTAssertEqual(checker.availableVersion?.tag, version.tag)

        let relaunched = UpdateChecker(releaseTag: "v0.9.1120", defaults: defaults)
        XCTAssertEqual(relaunched.upgradeToOffer?.tag, version.tag)
    }

    @MainActor
    func testSkippingAnUpgradeKeepsItInTheMenuAndAllowsNewerPrompts() async throws {
        let defaults = MemoryDefaults()
        let checker = UpdateChecker(releaseTag: "v0.9.1120", defaults: defaults) {
            ReleaseVersion(tag: "v0.9.1121")!
        }

        _ = await checker.check(manual: true)
        let version = try XCTUnwrap(checker.upgradeToOffer)
        checker.markUpgradeOffered(version)
        checker.skipUpgrade(version)

        let relaunched = UpdateChecker(releaseTag: "v0.9.1120", defaults: defaults) {
            ReleaseVersion(tag: "v0.9.1122")!
        }
        XCTAssertNil(relaunched.upgradeToOffer)
        XCTAssertEqual(relaunched.availableVersion?.tag, version.tag)

        _ = await relaunched.check(manual: true)
        XCTAssertEqual(relaunched.upgradeToOffer?.tag, "v0.9.1122")
    }

    @MainActor
    func testLaterRestoresRemindersForAPreviouslySkippedUpgrade() async throws {
        let defaults = MemoryDefaults()
        let checker = UpdateChecker(releaseTag: "v0.9.1120", defaults: defaults) {
            ReleaseVersion(tag: "v0.9.1121")!
        }
        _ = await checker.check(manual: true)
        let version = try XCTUnwrap(checker.availableVersion)
        checker.skipUpgrade(version)

        let relaunched = UpdateChecker(releaseTag: "v0.9.1120", defaults: defaults)
        XCTAssertNil(relaunched.upgradeToOffer)
        relaunched.markUpgradeOffered(version)
        relaunched.deferUpgrade(version)
        XCTAssertNil(relaunched.upgradeToOffer)

        let nextLaunch = UpdateChecker(releaseTag: "v0.9.1120", defaults: defaults)
        XCTAssertEqual(nextLaunch.upgradeToOffer?.tag, version.tag)
    }

    @MainActor
    func testFailedAutomaticAttemptIsThrottledAcrossRestartsButManualCheckCanRetry() async {
        let defaults = MemoryDefaults()
        defaults.set(true, forKey: "UpdateChecks.Automatic")
        let firstAttempt = Date(timeIntervalSince1970: 86_400)
        let first = UpdateChecker(releaseTag: "v0.9.1113", defaults: defaults, now: { firstAttempt }) {
            throw URLError(.notConnectedToInternet)
        }
        guard case .failed = await first.check(manual: false) else {
            return XCTFail("Expected an offline failure")
        }

        var now = firstAttempt.addingTimeInterval(86_399)
        let relaunched = UpdateChecker(releaseTag: "v0.9.1113", defaults: defaults, now: { now }) {
            ReleaseVersion(tag: "v0.9.1113")!
        }
        guard case .skipped = await relaunched.check(manual: false),
              case .current = await relaunched.check(manual: true) else {
            return XCTFail("Expected only the manual check to run")
        }
        now = firstAttempt.addingTimeInterval(86_400)
        guard case .current = await relaunched.check(manual: false) else {
            return XCTFail("Expected automatic checks to resume after 24 hours")
        }
    }

    @MainActor
    func testDisablingAutomaticChecksCancelsTheRequest() async {
        let defaults = MemoryDefaults()
        defaults.set(true, forKey: "UpdateChecks.Automatic")
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let checker = UpdateChecker(releaseTag: "v0.9.1113", defaults: defaults) {
            continuation.yield(())
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return ReleaseVersion(tag: "v0.9.1114")!
        }
        let check = Task { await checker.check(manual: false) }
        for await _ in started { break }
        XCTAssertTrue(checker.isChecking)
        checker.setAutomaticChecks(false)
        guard case .skipped = await check.value else { return XCTFail("Expected cancellation") }
        XCTAssertFalse(checker.isChecking)
        XCTAssertNil(checker.availableVersion)
        XCTAssertEqual(UpdateChecker(releaseTag: "v0.9.1113", defaults: defaults).automaticPreference, false)
    }

    @MainActor
    func testLocalBuildDoesNotContactGitHub() async {
        let checker = UpdateChecker(releaseTag: nil, defaults: MemoryDefaults()) {
            XCTFail("No request should be made for a local build")
            throw URLError(.unknown)
        }
        guard case .unversionedBuild = await checker.check(manual: true) else {
            return XCTFail("Expected an unversioned build result")
        }
    }
}

private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
