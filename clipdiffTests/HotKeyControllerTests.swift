import Carbon
import XCTest
@testable import ClipDiffCore

@MainActor
final class HotKeyControllerTests: XCTestCase {
    func testStartupConflictIsRejectedBeforeRegistrationAndCanBeRetried() async {
        let backend = FakeHotKeyBackend()
        var conflict: GlobalShortcutError? = .systemShortcut
        let controller = HotKeyController(
            shortcut: .defaultShortcut, backend: backend, validate: { _ in conflict }, action: {}
        )
        XCTAssertFalse(controller.isRegistered)
        XCTAssertNil(controller.registeredShortcut)
        XCTAssertEqual(controller.lastError, .systemShortcut)
        XCTAssertEqual(backend.events, ["install"])

        conflict = nil
        XCTAssertTrue(controller.updateShortcut(.defaultShortcut))
        XCTAssertTrue(controller.isRegistered)
        XCTAssertNil(controller.lastError)
        XCTAssertEqual(backend.events, ["install", "register"])
    }

    func testRejectedReplacementAndDefaultKeepTheWorkingShortcut() async {
        let backend = FakeHotKeyBackend()
        var conflict: GlobalShortcutError?
        let controller = HotKeyController(
            shortcut: alternative, backend: backend, validate: { _ in conflict }, action: {}
        )
        conflict = .menuItem("Copy")
        XCTAssertFalse(controller.updateShortcut(.defaultShortcut))
        XCTAssertEqual(controller.registeredShortcut, alternative)
        XCTAssertEqual(controller.lastError, conflict)
        XCTAssertEqual(backend.events, ["install", "register"])

        conflict = nil
        backend.result = .success(OpaquePointer(bitPattern: 2)!)
        XCTAssertTrue(controller.updateShortcut(.defaultShortcut))
        XCTAssertEqual(controller.registeredShortcut, .defaultShortcut)
        XCTAssertEqual(backend.events, ["install", "register", "register", "unregister:1"])
    }

    func testSavingCurrentShortcutRechecksChangedSystemSettings() async {
        let backend = FakeHotKeyBackend()
        var conflict: GlobalShortcutError?
        let controller = HotKeyController(
            shortcut: .defaultShortcut, backend: backend, validate: { _ in conflict }, action: {}
        )
        conflict = .systemShortcut
        XCTAssertFalse(controller.updateShortcut(.defaultShortcut))
        XCTAssertEqual(controller.lastError, .systemShortcut)
        XCTAssertEqual(backend.events, ["install", "register"])
    }

    func testFailedReplacementKeepsWorkingRegistration() async {
        let backend = FakeHotKeyBackend()
        let controller = HotKeyController(shortcut: .defaultShortcut, backend: backend, action: {})
        backend.result = .failure(.alreadyRegistered)

        XCTAssertFalse(controller.updateShortcut(alternative))
        XCTAssertTrue(controller.isRegistered)
        XCTAssertEqual(controller.registeredShortcut, .defaultShortcut)
        XCTAssertEqual(controller.lastError, .alreadyRegistered)
        XCTAssertEqual(backend.events, ["install", "register", "register"])
    }

    func testSuccessfulReplacementRegistersBeforeReleasingPreviousShortcut() async {
        let backend = FakeHotKeyBackend()
        let controller = HotKeyController(shortcut: .defaultShortcut, backend: backend, action: {})
        backend.result = .success(OpaquePointer(bitPattern: 2)!)

        XCTAssertTrue(controller.updateShortcut(alternative))
        XCTAssertEqual(controller.registeredShortcut, alternative)
        XCTAssertNil(controller.lastError)
        XCTAssertEqual(backend.events, ["install", "register", "register", "unregister:1"])
    }

    func testSavingSameShortcutDoesNotConflictWithItself() async {
        let backend = FakeHotKeyBackend()
        let controller = HotKeyController(shortcut: .defaultShortcut, backend: backend, action: {})
        backend.result = .failure(.alreadyRegistered)
        XCTAssertTrue(controller.updateShortcut(.defaultShortcut))
        XCTAssertEqual(backend.events, ["install", "register"])
    }

    func testStartupRegistrationFailureCanBeRecovered() async {
        let backend = FakeHotKeyBackend()
        backend.result = .failure(.registrationFailed(-50))
        let controller = HotKeyController(shortcut: .defaultShortcut, backend: backend, action: {})
        XCTAssertFalse(controller.isRegistered)
        XCTAssertNil(controller.registeredShortcut)
        XCTAssertEqual(controller.lastError, .registrationFailed(-50))

        backend.result = .success(OpaquePointer(bitPattern: 2)!)
        XCTAssertTrue(controller.updateShortcut(alternative))
        XCTAssertTrue(controller.isRegistered)
        XCTAssertNil(controller.lastError)
    }

    func testHandlerFailureDoesNotRegisterAnUnusableShortcut() async {
        let backend = FakeHotKeyBackend()
        backend.installStatus = -50
        let controller = HotKeyController(shortcut: .defaultShortcut, backend: backend, action: {})
        XCTAssertFalse(controller.isRegistered)
        XCTAssertFalse(controller.updateShortcut(alternative))
        XCTAssertEqual(controller.lastError, .eventHandlerFailed(-50))
        XCTAssertEqual(backend.events, ["install"])
    }

    func testShutdownReleasesCurrentRegistration() async {
        let backend = FakeHotKeyBackend()
        var controller: HotKeyController? = HotKeyController(shortcut: .defaultShortcut, backend: backend, action: {})
        XCTAssertTrue(controller!.isRegistered)
        controller = nil
        XCTAssertEqual(backend.events, ["install", "register", "unregister:1"])
    }

    func testOnlyDuplicateRegistrationErrorsAreReportedAsConflicts() async {
        XCTAssertEqual(GlobalShortcutError.registrationFailure(OSStatus(eventHotKeyExistsErr)), .alreadyRegistered)
        XCTAssertEqual(GlobalShortcutError.registrationFailure(-50), .registrationFailed(-50))
    }

    private var alternative: GlobalShortcut {
        GlobalShortcut(keyCode: 8, modifiers: [.command, .control])!
    }
}

private final class FakeHotKeyBackend: HotKeyBackend {
    var events: [String] = []
    var installStatus: OSStatus = noErr
    var result: Result<EventHotKeyRef, GlobalShortcutError> = .success(OpaquePointer(bitPattern: 1)!)

    func installEventHandler(action: @escaping () -> Void) -> OSStatus {
        events.append("install")
        return installStatus
    }

    func register(_ shortcut: GlobalShortcut) -> Result<EventHotKeyRef, GlobalShortcutError> {
        events.append("register")
        return result
    }

    func unregister(_ reference: EventHotKeyRef) {
        events.append("unregister:\(Int(bitPattern: reference))")
    }
}
