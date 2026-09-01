import Foundation
import XCTest
@testable import ClipDiffCore

final class ExternalDiffSettingsTests: XCTestCase {
    func testPersistsOnlyViewerPathAndWarningAcknowledgement() throws {
        let suiteName = "ClipDiffTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExternalDiffSettingsStore(defaults: defaults)

        store.save(
            ExternalDiffSettings(
                selectedExecutablePath: "/Applications/Diff.app/Contents/MacOS/diff",
                plaintextWarningAcknowledged: true
            )
        )

        XCTAssertEqual(
            store.load(),
            ExternalDiffSettings(
                selectedExecutablePath: "/Applications/Diff.app/Contents/MacOS/diff",
                plaintextWarningAcknowledged: true
            )
        )
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("ExternalDiff.")
        }.sorted(), [
            "ExternalDiff.PlaintextWarningAcknowledged",
            "ExternalDiff.SelectedExecutablePath"
        ])
    }

    func testSelectingBuiltInViewerClearsOnlyExecutablePath() throws {
        let suiteName = "ClipDiffTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExternalDiffSettingsStore(defaults: defaults)

        store.save(
            ExternalDiffSettings(
                selectedExecutablePath: nil,
                plaintextWarningAcknowledged: true
            )
        )

        XCTAssertEqual(
            store.load(),
            ExternalDiffSettings(
                selectedExecutablePath: nil,
                plaintextWarningAcknowledged: true
            )
        )
    }
}
