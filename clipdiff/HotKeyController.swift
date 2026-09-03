import Carbon
import Foundation

private let clipDiffHotKeySignature: OSType = 0x434C4446
private let clipDiffHotKeyID: UInt32 = 1

final class HotKeyController {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let action: () -> Void

    private(set) var isRegistered = false
    private(set) var registeredShortcut: GlobalShortcut?

    init(shortcut: GlobalShortcut, action: @escaping () -> Void) {
        self.action = action
        installEventHandler()
        isRegistered = registerHotKey(shortcut)
        if isRegistered {
            registeredShortcut = shortcut
        }
    }

    deinit {
        unregisterHotKey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    @discardableResult
    func updateShortcut(_ shortcut: GlobalShortcut) -> Bool {
        let previousShortcut = registeredShortcut
        unregisterHotKey()

        if registerHotKey(shortcut) {
            registeredShortcut = shortcut
            isRegistered = true
            return true
        }

        if let previousShortcut, registerHotKey(previousShortcut) {
            registeredShortcut = previousShortcut
            isRegistered = true
        } else {
            registeredShortcut = nil
            isRegistered = false
        }
        return false
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                let controller = Unmanaged<HotKeyController>
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

                controller.action()
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
    }

    private func registerHotKey(_ shortcut: GlobalShortcut) -> Bool {
        let hotKeyID = EventHotKeyID(
            signature: clipDiffHotKeySignature,
            id: clipDiffHotKeyID
        )

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers(for: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            hotKeyRef = nil
        }
        return status == noErr
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func carbonModifiers(for modifiers: GlobalShortcut.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
