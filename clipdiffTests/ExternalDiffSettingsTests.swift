import Foundation
import XCTest
@testable import ClipDiffCore

final class ExternalDiffSettingsTests: XCTestCase {
    func testPersistsViewerPreferencesAndRecommendationOverride() throws {
        let suiteName = "ClipDiffTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExternalDiffSettingsStore(defaults: defaults)

        store.save(
            ExternalDiffSettings(
                selectedExecutablePath: "/Applications/Diff.app/Contents/MacOS/diff",
                plaintextWarningAcknowledged: true,
                forceMacDiffRecommendation: true
            )
        )

        XCTAssertEqual(
            store.load(),
            ExternalDiffSettings(
                selectedExecutablePath: "/Applications/Diff.app/Contents/MacOS/diff",
                plaintextWarningAcknowledged: true,
                forceMacDiffRecommendation: true
            )
        )
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("ExternalDiff.")
        }.sorted(), [
            "ExternalDiff.ForceMacDiffRecommendation",
            "ExternalDiff.PlaintextWarningAcknowledged",
            "ExternalDiff.SelectedExecutablePath"
        ])
    }

    func testSelectingBuiltInViewerClearsOnlyExecutablePath() throws {
        let suiteName = "ClipDiffTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExternalDiffSettingsStore(defaults: defaults)

        defaults.set("/Applications/Diff.app/Contents/MacOS/diff", forKey: "ExternalDiff.SelectedExecutablePath")
        defaults.set(true, forKey: "ExternalDiff.PlaintextWarningAcknowledged")
        defaults.set(true, forKey: "ExternalDiff.ForceMacDiffRecommendation")

        var settings = store.load()
        settings.selectedExecutablePath = nil
        store.save(settings)

        XCTAssertEqual(
            store.load(),
            ExternalDiffSettings(
                selectedExecutablePath: nil,
                plaintextWarningAcknowledged: true,
                forceMacDiffRecommendation: true
            )
        )
    }

    func testRecommendationOverrideIsOffForExistingPreferences() throws {
        let suiteName = "ClipDiffTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("/Applications/Diff.app/Contents/MacOS/diff", forKey: "ExternalDiff.SelectedExecutablePath")
        defaults.set(true, forKey: "ExternalDiff.PlaintextWarningAcknowledged")

        let settings = ExternalDiffSettingsStore(defaults: defaults).load()

        XCTAssertFalse(settings.forceMacDiffRecommendation)
    }

    func testRecommendsMacDiffWithoutDedicatedViewers() {
        let settings = ExternalDiffSettings(selectedExecutablePath: nil, plaintextWarningAcknowledged: false)
        let editors = ExternalDiffToolCatalog.tools.filter { ["vscode", "cursor"].contains($0.id) }

        XCTAssertTrue(settings.shouldRecommendMacDiff(among: []))
        for editor in editors {
            XCTAssertTrue(settings.shouldRecommendMacDiff(among: [choice(for: editor)]), editor.id)
        }
        XCTAssertTrue(settings.shouldRecommendMacDiff(among: editors.map(choice(for:))))
    }

    func testDedicatedViewersSuppressRecommendationEvenWhenNotSelected() {
        let settings = ExternalDiffSettings(selectedExecutablePath: nil, plaintextWarningAcknowledged: false)
        let dedicatedIDs = [
            "macdiff", "filemerge", "kaleidoscope", "beyond-compare", "araxis", "bbedit",
            "kdiff3", "meld", "p4merge", "diffmerge"
        ]

        for tool in ExternalDiffToolCatalog.tools where dedicatedIDs.contains(tool.id) {
            XCTAssertFalse(settings.shouldRecommendMacDiff(among: [choice(for: tool)]), tool.id)
        }
        XCTAssertFalse(settings.shouldRecommendMacDiff(among: ExternalDiffToolCatalog.tools.map(choice(for:))))
    }

    func testManuallyChosenCustomViewerSuppressesRecommendation() {
        let settings = ExternalDiffSettings(selectedExecutablePath: nil, plaintextWarningAcknowledged: false)
        let custom = ExternalDiffToolCatalog.matchExecutable(at: URL(fileURLWithPath: "/Tools/MyDiff"))

        XCTAssertFalse(settings.shouldRecommendMacDiff(among: [choice(for: custom)]))
    }

    func testForceRecommendationOverridesInstalledViewers() {
        let settings = ExternalDiffSettings(
            selectedExecutablePath: nil,
            plaintextWarningAcknowledged: false,
            forceMacDiffRecommendation: true
        )

        XCTAssertTrue(settings.shouldRecommendMacDiff(among: ExternalDiffToolCatalog.tools.map(choice(for:))))
    }

    private func choice(for tool: ExternalDiffTool) -> ExternalDiffToolChoice {
        ExternalDiffToolChoice(tool: tool, executableURL: URL(fileURLWithPath: "/Tools/\(tool.id)"))
    }
}
