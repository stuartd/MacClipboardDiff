import Foundation

struct ExternalDiffSettings: Equatable {
    var selectedExecutablePath: String?
    var plaintextWarningAcknowledged: Bool
    var forceMacDiffRecommendation = false

    func shouldRecommendMacDiff(among installedTools: [ExternalDiffToolChoice]) -> Bool {
        forceMacDiffRecommendation || !installedTools.contains { $0.tool.isDedicatedDiffViewer }
    }
}

final class ExternalDiffSettingsStore {
    private enum Key {
        static let selectedExecutablePath = "ExternalDiff.SelectedExecutablePath"
        static let plaintextWarningAcknowledged = "ExternalDiff.PlaintextWarningAcknowledged"
        static let forceMacDiffRecommendation = "ExternalDiff.ForceMacDiffRecommendation"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ExternalDiffSettings {
        ExternalDiffSettings(
            selectedExecutablePath: defaults.string(forKey: Key.selectedExecutablePath),
            plaintextWarningAcknowledged: defaults.bool(forKey: Key.plaintextWarningAcknowledged),
            forceMacDiffRecommendation: defaults.bool(forKey: Key.forceMacDiffRecommendation)
        )
    }

    func save(_ settings: ExternalDiffSettings) {
        if let selectedExecutablePath = settings.selectedExecutablePath {
            defaults.set(selectedExecutablePath, forKey: Key.selectedExecutablePath)
        } else {
            defaults.removeObject(forKey: Key.selectedExecutablePath)
        }
        defaults.set(
            settings.plaintextWarningAcknowledged,
            forKey: Key.plaintextWarningAcknowledged
        )
        defaults.set(
            settings.forceMacDiffRecommendation,
            forKey: Key.forceMacDiffRecommendation
        )
    }
}
