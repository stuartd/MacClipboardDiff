import AppKit
import SwiftUI

@MainActor
final class ShortcutSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let controller: ClipDiffController

    init(controller: ClipDiffController) {
        self.controller = controller

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keyboard Shortcut"
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

        window.contentView = NSHostingView(
            rootView: ShortcutSettingsView(
                initialShortcut: controller.globalShortcut,
                save: { [weak self] shortcut in
                    guard let self, self.controller.setGlobalShortcut(shortcut) else {
                        return false
                    }
                    self.close()
                    return true
                },
                cancel: { [weak self] in
                    self?.close()
                }
            )
        )
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct ShortcutSettingsView: View {
    @State private var shortcut: GlobalShortcut
    @State private var saveError: String?
    let save: (GlobalShortcut) -> Bool
    let cancel: () -> Void

    init(
        initialShortcut: GlobalShortcut,
        save: @escaping (GlobalShortcut) -> Bool,
        cancel: @escaping () -> Void
    ) {
        _shortcut = State(initialValue: initialShortcut)
        self.save = save
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Show Diff shortcut")
                .font(.headline)

            ShortcutRecorderView(shortcut: $shortcut)
                .frame(height: 52)

            Text(saveError ?? "Press a letter, number, or punctuation key with ⌘, ⌥, or ⌃.")
                .font(.caption)
                .foregroundStyle(saveError == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Button("Use Default") {
                    shortcut = .defaultShortcut
                    saveError = nil
                }

                Spacer()

                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if !save(shortcut) {
                        saveError = "That shortcut is already in use. Choose another one."
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430, height: 230)
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.shortcut = shortcut
        view.onChange = { newShortcut in
            shortcut = newShortcut
        }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcut = shortcut
    }
}

private final class RecorderView: NSView {
    var shortcut = GlobalShortcut.defaultShortcut {
        didSet {
            setAccessibilityValue(shortcut.displayString)
            needsDisplay = true
        }
    }
    var onChange: ((GlobalShortcut) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Show Diff keyboard shortcut")
        setAccessibilityValue(shortcut.displayString)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !capture(event) {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        capture(event) || super.performKeyEquivalent(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        path.fill()

        (window?.firstResponder === self ? NSColor.controlAccentColor : NSColor.separatorColor)
            .setStroke()
        path.lineWidth = window?.firstResponder === self ? 2 : 1
        path.stroke()

        let text = shortcut.displayString as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: floor((self.bounds.width - size.width) / 2),
                y: floor((self.bounds.height - size.height) / 2)
            ),
            withAttributes: attributes
        )
    }

    private func capture(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: GlobalShortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }

        guard let newShortcut = GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        ) else {
            return false
        }

        shortcut = newShortcut
        onChange?(newShortcut)
        return true
    }
}
