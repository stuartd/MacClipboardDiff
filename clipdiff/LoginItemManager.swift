import AppKit
import Combine
import CoreServices
import ServiceManagement

@MainActor
protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

private struct SystemLoginItemService: LoginItemServicing {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
protocol LoginItemPromptStoring: AnyObject {
    var hasHandledPrompt: Bool { get set }
}

final class LoginItemPromptStore: LoginItemPromptStoring {
    private static let defaultsKey = "StartAtLogin.HasHandledPrompt"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasHandledPrompt: Bool {
        get { defaults.bool(forKey: Self.defaultsKey) }
        set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }
}

enum StartAtLoginPromptResponse {
    case enable
    case notNow
}

@MainActor
protocol LoginItemPromptPresenting {
    func askToEnableStartAtLogin() -> StartAtLoginPromptResponse
    func showLoginItemError(_ error: Error)
    func askToOpenLoginItems() -> Bool
}

private struct AppKitLoginItemPromptPresenter: LoginItemPromptPresenting {
    func askToEnableStartAtLogin() -> StartAtLoginPromptResponse {
        let alert = NSAlert()
        alert.messageText = "Start ClipDiff at login?"
        alert.informativeText = "ClipDiff needs to be running to capture the text and files you copy. Starting at login keeps it ready whenever you need a diff. You can change this later in the ClipDiff menu."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start at Login")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? .enable : .notNow
    }

    func showLoginItemError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t change Start at Login"
        alert.informativeText = "ClipDiff could not update whether it starts automatically. You can try again from the ClipDiff menu or manage it in System Settings > General > Login Items.\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func askToOpenLoginItems() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Allow ClipDiff to start at login"
        alert.informativeText = "macOS requires approval before ClipDiff can start automatically. Enable ClipDiff in System Settings > General > Login Items."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Reads the real macOS registration state; preferences only remember whether we asked.
@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status

    private let service: LoginItemServicing
    private let promptStore: LoginItemPromptStoring
    private let presenter: LoginItemPromptPresenting
    private var isAutomaticPromptSuppressed = false

    init(
        service: LoginItemServicing? = nil,
        promptStore: LoginItemPromptStoring? = nil,
        presenter: LoginItemPromptPresenting? = nil
    ) {
        let service = service ?? SystemLoginItemService()
        self.service = service
        self.promptStore = promptStore ?? LoginItemPromptStore()
        self.presenter = presenter ?? AppKitLoginItemPromptPresenter()
        status = service.status
    }

    var requiresApproval: Bool { status == .requiresApproval }

    // A pending registration can also be turned off. The menu explicitly labels
    // it as requiring approval rather than implying that macOS will launch it.
    var isRequested: Bool { status == .enabled || requiresApproval }

    func refreshStatus() {
        let currentStatus = service.status
        if currentStatus != status { status = currentStatus }
    }

    func setEnabled(_ enabled: Bool) {
        // A deliberate menu choice also answers the one-time question.
        promptStore.hasHandledPrompt = true
        refreshStatus()
        do {
            if enabled {
                if !isRequested { try service.register() }
            } else if isRequested {
                try service.unregister()
            }
        } catch {
            refreshStatus()
            presenter.showLoginItemError(error)
            return
        }
        refreshStatus()
        if enabled, requiresApproval, presenter.askToOpenLoginItems() {
            openSystemSettings()
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }

    /// Login launches and Finder comparisons stay quiet. An unanswered question
    /// is deferred until the next ordinary launch, without persisting a refusal.
    func suppressAutomaticPrompt() {
        isAutomaticPromptSuppressed = true
    }

    func promptIfNeeded() {
        refreshStatus()
        guard !isAutomaticPromptSuppressed, !promptStore.hasHandledPrompt else { return }
        // Mark before presenting: modal alerts run a nested event loop.
        promptStore.hasHandledPrompt = true
        guard !isRequested else { return }
        if presenter.askToEnableStartAtLogin() == .enable {
            setEnabled(true)
        }
    }
}

enum LoginItemLaunchContext {
    static func isAutomaticLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == kAEOpenApplication,
              let source = event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue else {
            return false
        }
        return source == keyAELaunchedAsLogInItem || source == keyAELaunchedAsServiceItem
    }
}
