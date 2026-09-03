import Foundation

final class ClipboardHistory {
    static let defaultRecentClearWindow: TimeInterval = 60

    private(set) var entries: [ClipboardEntry] = []
    private(set) var isMonitoring = true
    private(set) var lastChangeCount: Int

    private let recentClearWindow: TimeInterval
    private var clearEligibility: ClearEligibility?

    init(
        startupChangeCount: Int = 0,
        recentClearWindow: TimeInterval = ClipboardHistory.defaultRecentClearWindow
    ) {
        lastChangeCount = startupChangeCount
        self.recentClearWindow = recentClearWindow
    }

    var currentEntry: ClipboardEntry? {
        entries.first
    }

    var previousEntry: ClipboardEntry? {
        entries.dropFirst().first
    }

    var canDiff: Bool {
        previousEntry != nil && currentEntry != nil
    }

    var statusText: String {
        if !isMonitoring {
            return "Monitoring paused"
        }

        switch entries.count {
        case 0:
            return "Waiting for copied text"
        case 1:
            return "Copy one more text value"
        default:
            return "Ready to diff"
        }
    }

    @discardableResult
    func apply(_ observation: ClipboardObservation) -> ClipboardHistoryChange {
        guard isMonitoring else { return .none }
        guard observation.changeCount != lastChangeCount else { return .none }

        lastChangeCount = observation.changeCount

        switch observation.content {
        case .value(let value):
            guard !value.text.isEmpty else {
                return applyExplicitClear(observedAt: observation.observedAt)
            }
            return insert(value, capturedAt: observation.observedAt)

        case .pair(let previousValue, let currentValue):
            guard !previousValue.text.isEmpty, !currentValue.text.isEmpty else {
                clearEligibility = nil
                return .none
            }

            let previous = makeEntry(from: previousValue, capturedAt: observation.observedAt)
            let current = makeEntry(from: currentValue, capturedAt: observation.observedAt)
            entries = [current, previous]
            clearEligibility = ClearEligibility(
                entryID: current.id,
                observedAt: observation.observedAt
            )
            return .accepted

        case .explicitClear:
            return applyExplicitClear(observedAt: observation.observedAt)

        case .nonText, .ownWrite:
            clearEligibility = nil
            return .none
        }
    }

    func pause() {
        isMonitoring = false
        clearEligibility = nil
    }

    func resume(currentChangeCount: Int) {
        isMonitoring = true
        lastChangeCount = currentChangeCount
        clearEligibility = nil
    }

    func clearCapturedText() {
        entries.removeAll()
        clearEligibility = nil
    }

    func replaceComparisonPair(
        previous previousValue: CapturedClipboardValue,
        current currentValue: CapturedClipboardValue,
        capturedAt: Date
    ) {
        entries = [
            makeEntry(from: currentValue, capturedAt: capturedAt),
            makeEntry(from: previousValue, capturedAt: capturedAt)
        ]
        clearEligibility = nil
    }

    private func insert(
        _ value: CapturedClipboardValue,
        capturedAt: Date
    ) -> ClipboardHistoryChange {
        let entry = makeEntry(from: value, capturedAt: capturedAt)
        entries.insert(entry, at: 0)

        if entries.count > 2 {
            entries.removeLast(entries.count - 2)
        }

        clearEligibility = ClearEligibility(entryID: entry.id, observedAt: capturedAt)
        return .accepted
    }

    private func makeEntry(
        from value: CapturedClipboardValue,
        capturedAt: Date
    ) -> ClipboardEntry {
        ClipboardEntry(
            text: value.text,
            capturedAt: capturedAt,
            sourceFileName: value.sourceFileName,
            sourceFilePath: value.sourceFilePath
        )
    }

    private func applyExplicitClear(observedAt: Date) -> ClipboardHistoryChange {
        guard let eligibility = clearEligibility,
              currentEntry?.id == eligibility.entryID,
              observedAt >= eligibility.observedAt,
              observedAt.timeIntervalSince(eligibility.observedAt) <= recentClearWindow else {
            clearEligibility = nil
            return .none
        }

        entries.removeFirst()
        clearEligibility = nil
        return .removedByRecentClear
    }
}

private struct ClearEligibility {
    let entryID: UUID
    let observedAt: Date
}
