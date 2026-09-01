import Foundation

struct ExternalDiffSettings: Equatable {
    var selectedExecutablePath: String?
    var plaintextWarningAcknowledged: Bool
}

final class ExternalDiffSettingsStore {
    private enum Key {
        static let selectedExecutablePath = "ExternalDiff.SelectedExecutablePath"
        static let plaintextWarningAcknowledged = "ExternalDiff.PlaintextWarningAcknowledged"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ExternalDiffSettings {
        ExternalDiffSettings(
            selectedExecutablePath: defaults.string(forKey: Key.selectedExecutablePath),
            plaintextWarningAcknowledged: defaults.bool(forKey: Key.plaintextWarningAcknowledged)
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
    }
}
