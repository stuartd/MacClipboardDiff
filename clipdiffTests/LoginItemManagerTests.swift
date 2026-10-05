import AppKit
import CoreServices
import ServiceManagement
import XCTest
@testable import ClipDiffCore

@MainActor
final class LoginItemManagerTests: XCTestCase {
    func testAcceptingPromptRegistersAndDoesNotAskAgainAfterRelaunch() async {
        let fixture = Fixture(response: .enable)
        fixture.manager.promptIfNeeded()
        XCTAssertEqual(fixture.service.registerCount, 1)
        XCTAssertEqual(fixture.manager.status, .enabled)
        XCTAssertTrue(fixture.store.hasHandledPrompt)

        // An external change after acceptance must not trigger another prompt
        // or automatically restore the user's login-item registration.
        fixture.service.status = .notRegistered
        fixture.relaunchedManager().promptIfNeeded()
        XCTAssertEqual(fixture.presenter.promptCount, 1)
        XCTAssertEqual(fixture.service.registerCount, 1)
    }

    func testDecliningPromptIsRememberedAcrossRelaunches() async {
        let fixture = Fixture(response: .notNow)
        fixture.manager.promptIfNeeded()
        fixture.manager.promptIfNeeded()
        fixture.relaunchedManager().promptIfNeeded()
        XCTAssertEqual(fixture.presenter.promptCount, 1)
        XCTAssertTrue(fixture.store.hasHandledPrompt)
        XCTAssertEqual(fixture.service.registerCount, 0)
        XCTAssertEqual(fixture.manager.status, .notRegistered)
    }

    func testAlreadyEnabledSkipsPromptAndDoesNotAskAfterExternalDisable() async {
        let fixture = Fixture(status: .enabled)
        fixture.manager.promptIfNeeded()
        XCTAssertTrue(fixture.store.hasHandledPrompt)
        fixture.service.status = .notRegistered
        fixture.relaunchedManager().promptIfNeeded()
        XCTAssertEqual(fixture.presenter.promptCount, 0)
        XCTAssertEqual(fixture.service.registerCount, 0)
    }

    func testPendingApprovalSkipsAutomaticPromptAndDoesNotNag() async {
        let fixture = Fixture(status: .requiresApproval)
        fixture.manager.promptIfNeeded()
        fixture.relaunchedManager().promptIfNeeded()
        XCTAssertTrue(fixture.manager.requiresApproval)
        XCTAssertTrue(fixture.manager.isRequested)
        XCTAssertTrue(fixture.store.hasHandledPrompt)
        XCTAssertEqual(fixture.presenter.promptCount, 0)
        XCTAssertEqual(fixture.presenter.approvalPromptCount, 0)
        XCTAssertEqual(fixture.service.registerCount, 0)
    }

    func testMenuToggleEnablesAndDisablesWithoutRepeatingRegistration() async {
        let fixture = Fixture()
        fixture.manager.setEnabled(true)
        fixture.manager.setEnabled(true)
        XCTAssertEqual(fixture.manager.status, .enabled)
        XCTAssertTrue(fixture.manager.isRequested)
        XCTAssertEqual(fixture.service.registerCount, 1)

        fixture.manager.setEnabled(false)
        fixture.manager.setEnabled(false)
        XCTAssertEqual(fixture.manager.status, .notRegistered)
        XCTAssertFalse(fixture.manager.isRequested)
        XCTAssertEqual(fixture.service.unregisterCount, 1)
        fixture.relaunchedManager().promptIfNeeded()
        XCTAssertEqual(fixture.presenter.promptCount, 0)
    }

    func testRefreshFollowsExternalChangesWithoutMutatingRegistration() async {
        let fixture = Fixture()
        for status: SMAppService.Status in [.enabled, .requiresApproval, .notRegistered, .notFound] {
            fixture.service.status = status
            fixture.manager.refreshStatus()
            XCTAssertEqual(fixture.manager.status, status)
            XCTAssertEqual(fixture.manager.isRequested, status == .enabled || status == .requiresApproval)
            XCTAssertEqual(fixture.manager.requiresApproval, status == .requiresApproval)
        }
        XCTAssertEqual(fixture.service.registerCount, 0)
        XCTAssertEqual(fixture.service.unregisterCount, 0)
        XCTAssertFalse(fixture.store.hasHandledPrompt)
    }

    func testToggleReadsExternalStateBeforeDisabling() async {
        let fixture = Fixture()
        fixture.service.status = .enabled
        fixture.manager.setEnabled(false)
        XCTAssertEqual(fixture.service.unregisterCount, 1)
        XCTAssertEqual(fixture.manager.status, .notRegistered)
    }

    func testRegistrationFailureLeavesToggleOffAndReportsErrorOnce() async {
        let fixture = Fixture(response: .enable)
        fixture.service.registrationError = TestError.failed
        fixture.manager.promptIfNeeded()
        XCTAssertFalse(fixture.manager.isRequested)
        XCTAssertEqual(fixture.presenter.errors.count, 1)
        XCTAssertTrue(fixture.store.hasHandledPrompt)
        fixture.relaunchedManager().promptIfNeeded()
        XCTAssertEqual(fixture.presenter.promptCount, 1)

        fixture.service.registrationError = nil
        fixture.manager.setEnabled(true)
        XCTAssertEqual(fixture.manager.status, .enabled)
        XCTAssertEqual(fixture.service.registerCount, 2)
    }

    func testUnregistrationFailureKeepsActualEnabledState() async {
        let fixture = Fixture(status: .enabled)
        fixture.service.unregistrationError = TestError.failed
        fixture.manager.setEnabled(false)
        XCTAssertTrue(fixture.manager.isRequested)
        XCTAssertEqual(fixture.manager.status, .enabled)
        XCTAssertEqual(fixture.presenter.errors.count, 1)
    }

    func testApprovalRequiredOffersSettingsAndReflectsPendingState() async {
        let fixture = Fixture(response: .enable)
        fixture.service.statusAfterRegistration = .requiresApproval
        fixture.presenter.shouldOpenSettings = true
        fixture.manager.promptIfNeeded()
        XCTAssertEqual(fixture.manager.status, .requiresApproval)
        XCTAssertTrue(fixture.manager.requiresApproval)
        XCTAssertTrue(fixture.manager.isRequested)
        XCTAssertEqual(fixture.presenter.approvalPromptCount, 1)
        XCTAssertEqual(fixture.service.openSettingsCount, 1)
        XCTAssertTrue(fixture.presenter.errors.isEmpty)
    }

    func testDecliningApprovalGuidanceDoesNotOpenSettingsOrRepeatPrompt() async {
        let fixture = Fixture(response: .enable)
        fixture.service.statusAfterRegistration = .requiresApproval
        fixture.manager.promptIfNeeded()
        fixture.relaunchedManager().promptIfNeeded()
        XCTAssertEqual(fixture.presenter.approvalPromptCount, 1)
        XCTAssertEqual(fixture.presenter.promptCount, 1)
        XCTAssertEqual(fixture.service.openSettingsCount, 0)
    }

    func testPendingRegistrationCanBeCancelledFromMenu() async {
        let fixture = Fixture(status: .requiresApproval)
        fixture.manager.setEnabled(false)
        XCTAssertEqual(fixture.service.unregisterCount, 1)
        XCTAssertFalse(fixture.manager.isRequested)
        XCTAssertFalse(fixture.manager.requiresApproval)
        fixture.relaunchedManager().promptIfNeeded()
        XCTAssertEqual(fixture.presenter.promptCount, 0)
    }

    func testEnablingPendingRegistrationOffersSettingsWithoutReregistering() async {
        let fixture = Fixture(status: .requiresApproval)
        fixture.presenter.shouldOpenSettings = true
        fixture.manager.setEnabled(true)
        XCTAssertEqual(fixture.service.registerCount, 0)
        XCTAssertEqual(fixture.presenter.approvalPromptCount, 1)
        XCTAssertEqual(fixture.service.openSettingsCount, 1)
    }

    func testMissingRegistrationCanBeRetriedFromMenu() async {
        let fixture = Fixture(status: .notFound)
        fixture.manager.setEnabled(true)
        XCTAssertEqual(fixture.service.registerCount, 1)
        XCTAssertEqual(fixture.manager.status, .enabled)
    }

    func testOpeningSettingsDoesNotChangeRegistration() async {
        let fixture = Fixture(status: .requiresApproval)
        fixture.manager.openSystemSettings()
        XCTAssertEqual(fixture.service.openSettingsCount, 1)
        XCTAssertEqual(fixture.service.registerCount, 0)
        XCTAssertEqual(fixture.service.unregisterCount, 0)
    }

    func testQuietLaunchDefersUnansweredPromptUntilNextOrdinaryLaunch() async {
        let fixture = Fixture()
        fixture.manager.suppressAutomaticPrompt()
        fixture.manager.promptIfNeeded()
        fixture.manager.refreshStatus()
        fixture.manager.promptIfNeeded()
        XCTAssertEqual(fixture.presenter.promptCount, 0)
        XCTAssertFalse(fixture.store.hasHandledPrompt)
        XCTAssertEqual(fixture.service.registerCount, 0)

        fixture.relaunchedManager().promptIfNeeded()
        XCTAssertEqual(fixture.presenter.promptCount, 1)
        XCTAssertTrue(fixture.store.hasHandledPrompt)
    }

    func testMenuToggleStillWorksDuringQuietLaunch() async {
        let fixture = Fixture()
        fixture.manager.suppressAutomaticPrompt()
        fixture.manager.setEnabled(true)
        fixture.manager.promptIfNeeded()
        XCTAssertEqual(fixture.manager.status, .enabled)
        XCTAssertEqual(fixture.service.registerCount, 1)
        XCTAssertEqual(fixture.presenter.promptCount, 0)
    }

    func testPromptStorePersistsAnswerWithoutStoringEnabledState() async throws {
        let suiteName = "ClipDiffLoginItemTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LoginItemPromptStore(defaults: defaults)
        XCTAssertFalse(store.hasHandledPrompt)
        store.hasHandledPrompt = true
        XCTAssertTrue(LoginItemPromptStore(defaults: defaults).hasHandledPrompt)
        XCTAssertEqual(defaults.persistentDomain(forName: suiteName)?.count, 1)
    }

    func testLoginAndServiceLaunchEventsAreQuiet() async {
        for source in [keyAELaunchedAsLogInItem, keyAELaunchedAsServiceItem] {
            XCTAssertTrue(LoginItemLaunchContext.isAutomaticLaunch(launchEvent(source: source)))
        }
    }

    func testOrdinaryAndDocumentLaunchEventsAreNotLoginLaunches() async {
        XCTAssertFalse(LoginItemLaunchContext.isAutomaticLaunch(nil))
        XCTAssertFalse(LoginItemLaunchContext.isAutomaticLaunch(launchEvent()))
        XCTAssertFalse(LoginItemLaunchContext.isAutomaticLaunch(
            launchEvent(source: keyAELaunchedAsLogInItem, eventID: kAEOpenDocuments)
        ))
    }

    private func launchEvent(source: OSType? = nil, eventID: AEEventID = AEEventID(kAEOpenApplication)) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kCoreEventClass),
            eventID: eventID,
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if let source {
            event.setParam(NSAppleEventDescriptor(enumCode: source), forKeyword: keyAEPropData)
        }
        return event
    }
}

@MainActor
private struct Fixture {
    let service: FakeLoginItemService
    let store = FakeLoginItemPromptStore()
    let presenter = FakeLoginItemPromptPresenter()
    let manager: LoginItemManager

    init(status: SMAppService.Status = .notRegistered, response: StartAtLoginPromptResponse = .notNow) {
        service = FakeLoginItemService(status: status)
        presenter.response = response
        manager = LoginItemManager(service: service, promptStore: store, presenter: presenter)
    }

    func relaunchedManager() -> LoginItemManager {
        LoginItemManager(service: service, promptStore: store, presenter: presenter)
    }
}

private enum TestError: Error { case failed }

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status
    var statusAfterRegistration: SMAppService.Status = .enabled
    var registrationError: Error?
    var unregistrationError: Error?
    var registerCount = 0
    var unregisterCount = 0
    var openSettingsCount = 0

    init(status: SMAppService.Status) { self.status = status }

    func register() throws {
        registerCount += 1
        if let registrationError { throw registrationError }
        status = statusAfterRegistration
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregistrationError { throw unregistrationError }
        status = .notRegistered
    }

    func openSystemSettings() { openSettingsCount += 1 }
}

@MainActor
private final class FakeLoginItemPromptStore: LoginItemPromptStoring {
    var hasHandledPrompt = false
}

@MainActor
private final class FakeLoginItemPromptPresenter: LoginItemPromptPresenting {
    var response: StartAtLoginPromptResponse = .notNow
    var shouldOpenSettings = false
    var promptCount = 0
    var approvalPromptCount = 0
    var errors: [Error] = []

    func askToEnableStartAtLogin() -> StartAtLoginPromptResponse {
        promptCount += 1
        return response
    }

    func showLoginItemError(_ error: Error) { errors.append(error) }

    func askToOpenLoginItems() -> Bool {
        approvalPromptCount += 1
        return shouldOpenSettings
    }
}
