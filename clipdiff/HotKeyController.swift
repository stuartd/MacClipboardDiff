import Carbon
import Foundation

private let clipDiffHotKeySignature: OSType = 0x434C4446
private let clipDiffHotKeyID: UInt32 = 1

protocol HotKeyBackend: AnyObject {
    func installEventHandler(action: @escaping () -> Void) -> OSStatus
    func register(_ shortcut: GlobalShortcut) -> Result<EventHotKeyRef, GlobalShortcutError>
    func unregister(_ reference: EventHotKeyRef)
}

final class HotKeyController {
    private let backend: HotKeyBackend
    private var hotKeyRef: EventHotKeyRef?
    private let eventHandlerStatus: OSStatus

    var isRegistered: Bool { hotKeyRef != nil }
    private(set) var registeredShortcut: GlobalShortcut?
    private(set) var lastError: GlobalShortcutError?

    init(
        shortcut: GlobalShortcut,
        backend: HotKeyBackend = CarbonHotKeyBackend(),
        action: @escaping () -> Void
    ) {
        self.backend = backend
        eventHandlerStatus = backend.installEventHandler(action: action)
        updateShortcut(shortcut)
    }

    deinit {
        if let hotKeyRef {
            backend.unregister(hotKeyRef)
        }
    }

    @discardableResult
    func updateShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard eventHandlerStatus == noErr else {
            lastError = .eventHandlerFailed(eventHandlerStatus)
            return false
        }
        if registeredShortcut == shortcut {
            lastError = nil
            return true
        }

        // Keep the old registration until macOS accepts its replacement.
        switch backend.register(shortcut) {
        case .success(let reference):
            if let hotKeyRef {
                backend.unregister(hotKeyRef)
            }
            hotKeyRef = reference
            registeredShortcut = shortcut
            lastError = nil
            return true
        case .failure(let error):
            lastError = error
            return false
        }
    }
}

final class CarbonHotKeyBackend: HotKeyBackend {
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    deinit {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func installEventHandler(action: @escaping () -> Void) -> OSStatus {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        return InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                let backend = Unmanaged<CarbonHotKeyBackend>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else { return status }
                guard hotKeyID.signature == clipDiffHotKeySignature,
                      hotKeyID.id == clipDiffHotKeyID else {
                    return noErr
                }

                backend.action?()
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
    }

    func register(_ shortcut: GlobalShortcut) -> Result<EventHotKeyRef, GlobalShortcutError> {
        let hotKeyID = EventHotKeyID(
            signature: clipDiffHotKeySignature,
            id: clipDiffHotKeyID
        )

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &reference
        )

        guard status == noErr, let reference else {
            return .failure(.registrationFailure(status == noErr ? OSStatus(eventInternalErr) : status))
        }
        return .success(reference)
    }

    func unregister(_ reference: EventHotKeyRef) {
        UnregisterEventHotKey(reference)
    }
}
