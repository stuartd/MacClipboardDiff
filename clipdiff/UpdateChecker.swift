import Combine
import Foundation
import OSLog

@MainActor
final class UpdateChecker: ObservableObject {
    enum Outcome {
        case current
        case available(ReleaseVersion)
        case unversionedBuild
        case failed
        case skipped
    }

    private enum Key {
        static let automatic = "UpdateChecks.Automatic"
        static let lastAutomaticAttempt = "UpdateChecks.LastAutomaticAttempt"
        static let availableTag = "UpdateChecks.AvailableTag"
    }

    let installedVersion: ReleaseVersion?
    @Published private(set) var automaticPreference: Bool?
    @Published private(set) var availableVersion: ReleaseVersion?
    @Published private(set) var isChecking = false

    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetch: @Sendable () async throws -> ReleaseVersion
    private var timer: Timer?
    private var pending: Task<ReleaseVersion, Error>?
    private var pendingIsAutomatic = false

    init(
        releaseTag: String?,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        fetch: @escaping @Sendable () async throws -> ReleaseVersion = { try await GitHubReleaseClient.fetchLatest() }
    ) {
        let installed = releaseTag.flatMap(ReleaseVersion.init(tag:))
        installedVersion = installed
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
        automaticPreference = defaults.object(forKey: Key.automatic) as? Bool
        if let installed, let cachedTag = defaults.string(forKey: Key.availableTag),
           let cached = ReleaseVersion(tag: cachedTag), cached.isNewer(than: installed) {
            availableVersion = cached
        }
    }

    func start() {
        guard timer == nil else { return }
        checkAutomatically()
        guard installedVersion != nil else { return }
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { await self?.check(manual: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pending?.cancel()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.automatic)
        automaticPreference = enabled
        ClipDiffLog.updates.notice("Automatic update checks enabled=\(enabled, privacy: .public)")
        if enabled {
            checkAutomatically()
        } else if pendingIsAutomatic {
            pending?.cancel()
        }
    }

    func check(manual: Bool) async -> Outcome {
        let mode = manual ? "manual" : "automatic"
        let installedTag = installedVersion?.tag ?? "unknown"

        func decision(_ outcome: Outcome, _ reason: String) -> Outcome {
            ClipDiffLog.updates.notice(
                "Update check mode=\(mode, privacy: .public) installed=\(installedTag, privacy: .public) result=\(reason, privacy: .public)"
            )
            return outcome
        }

        guard let installedVersion else {
            return decision(.unversionedBuild, "unversioned build")
        }
        if !manual {
            guard automaticPreference == true else {
                return decision(.skipped, "automatic checks disabled")
            }
        }
        guard pending == nil else { return decision(.skipped, "check in progress") }
        if !manual {
            let attempt = now()
            if let last = defaults.object(forKey: Key.lastAutomaticAttempt) as? Date,
               attempt.timeIntervalSince(last) < 24 * 60 * 60 {
                return decision(.skipped, "within the 24-hour interval")
            }
            defaults.set(attempt, forKey: Key.lastAutomaticAttempt)
        }

        let request = Task { [fetch] in
            try Task.checkCancellation()
            return try await fetch()
        }
        pending = request
        pendingIsAutomatic = !manual
        isChecking = true
        defer {
            pending = nil
            pendingIsAutomatic = false
            isChecking = false
        }

        do {
            let published = try await request.value
            guard !request.isCancelled else { return decision(.skipped, "cancelled") }
            ClipDiffLog.updates.notice("GitHub published version=\(published.tag, privacy: .public)")
            guard published.isNewer(than: installedVersion) else {
                availableVersion = nil
                defaults.removeObject(forKey: Key.availableTag)
                return decision(.current, "up to date")
            }
            availableVersion = published
            defaults.set(published.tag, forKey: Key.availableTag)
            return decision(.available(published), "new release available")
        } catch {
            guard !request.isCancelled else { return decision(.skipped, "cancelled") }
            switch error {
            case GitHubReleaseClient.Failure.httpStatus(let code):
                ClipDiffLog.updates.error("Update request failed with HTTP status \(code, privacy: .public)")
            case GitHubReleaseClient.Failure.responseTooLarge:
                ClipDiffLog.updates.error("Update response exceeded the size limit")
            case GitHubReleaseClient.Failure.invalidResponse:
                ClipDiffLog.updates.error("Update response did not contain a valid stable release")
            default:
                ClipDiffLog.updates.error("Update request failed with code \((error as NSError).code, privacy: .public)")
            }
            return decision(.failed, "check failed")
        }
    }

    private func checkAutomatically() {
        Task { [weak self] in await self?.check(manual: false) }
    }
}
