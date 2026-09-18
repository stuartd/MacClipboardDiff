import AppKit
import SwiftUI

@MainActor
final class ShortcutSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let controller: ClipDiffController
    private var isPresenting = false

    init(controller: ClipDiffController) {
        self.controller = controller

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Change the keyboard shortcut"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }

        guard !isPresenting else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        isPresenting = true

        // Let the menu dismiss on the next default run-loop turn. Entering the
        // modal loop from a main-queue block would stall shortcut callbacks.
        perform(#selector(presentModalWindow), with: nil, afterDelay: 0)
    }

    @objc private func presentModalWindow() {
        guard let window else {
            isPresenting = false
            return
        }
        defer {
            window.orderOut(nil)
            isPresenting = false
        }

        window.contentView = NSHostingView(
            rootView: ShortcutSettingsView(
                initialShortcut: controller.globalShortcut,
                validate: { [controller] in controller.shortcutValidationError($0) },
                save: { [weak self] shortcut in
                    guard let self else { return .unavailable }
                    if let error = self.controller.setGlobalShortcut(shortcut) {
                        return error
                    }
                    self.close()
                    return nil
                },
                cancel: { [weak self] in
                    self?.close()
                }
            )
        )
        window.contentView?.layoutSubtreeIfNeeded()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.initialFirstResponder)
        NSApplication.shared.runModal(for: window)
    }

    func windowWillClose(_ notification: Notification) {
        guard NSApplication.shared.modalWindow === window else { return }
        // Includes Save, Cancel, Escape, and the title-bar close button.
        NSApplication.shared.stopModal()
    }

    func captureRegisteredShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard isPresenting else { return false }
        guard let window, window.isKeyWindow,
              let recorder = window.firstResponder as? ShortcutRecorderControl else {
            // Do not open another comparison while the shortcut dialog is modal.
            return true
        }
        return recorder.record(shortcut)
    }
}

private struct ShortcutSettingsView: View {
    @State private var shortcut: GlobalShortcut
    @State private var validationError: GlobalShortcutError?
    @State private var saveError: GlobalShortcutError?
    let validate: (GlobalShortcut) -> GlobalShortcutError?
    let save: (GlobalShortcut) -> GlobalShortcutError?
    let cancel: () -> Void

    init(
        initialShortcut: GlobalShortcut,
        validate: @escaping (GlobalShortcut) -> GlobalShortcutError?,
        save: @escaping (GlobalShortcut) -> GlobalShortcutError?,
        cancel: @escaping () -> Void
    ) {
        _shortcut = State(initialValue: initialShortcut)
        self.validate = validate
        self.save = save
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose the keyboard shortcut")
                .font(.headline)

            ShortcutRecorderView(shortcut: $shortcut)
                .frame(height: 52)

            Text((validationError ?? saveError)?.message ?? "Hold one or more of Command, Option and Control, then press a letter, number or punctuation key. You can also include Shift.")
                .font(.system(size: 14))
                .foregroundStyle(validationError == nil && saveError == nil ? Color.primary : Color.red)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Button("Use Default") {
                    shortcut = .defaultShortcut
                    validationError = validate(shortcut)
                    saveError = nil
                }

                Spacer()

                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveError = save(shortcut)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validationError != nil)
            }
        }
        .padding(20)
        .frame(width: 430, height: 260)
        .onAppear {
            validationError = validate(shortcut)
        }
        .onChange(of: shortcut) { newShortcut in
            validationError = validate(newShortcut)
            saveError = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have resolved a conflict in System Settings while
            // this window was open. Do not leave Save permanently disabled.
            validationError = validate(shortcut)
            saveError = nil
        }
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let view = ShortcutRecorderControl()
        view.shortcut = shortcut
        view.onChange = { newShortcut in
            shortcut = newShortcut
        }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderControl, context: Context) {
        view.shortcut = shortcut
    }
}
