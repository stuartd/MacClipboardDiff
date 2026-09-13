import AppKit
import SwiftUI

@MainActor
final class ShortcutSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let controller: ClipDiffController

    init(controller: ClipDiffController) {
        self.controller = controller

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 260),
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
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
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
            Text("Show Diff shortcut")
                .font(.headline)

            ShortcutRecorderView(shortcut: $shortcut)
                .frame(height: 52)

            Text((validationError ?? saveError)?.message ?? "Hold Command, Option or Control, then press a letter, number or punctuation key. You can add Shift too.")
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

        // Measure each key separately so wide modifier glyphs have a real gap.
        let keys = shortcut.displayString.map { String($0) as NSString }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let sizes = keys.map { $0.size(withAttributes: attributes) }
        let spacing: CGFloat = 10
        let totalWidth = sizes.reduce(0) { $0 + $1.width }
            + spacing * CGFloat(max(0, keys.count - 1))
        var x = floor((self.bounds.width - totalWidth) / 2)

        for (key, size) in zip(keys, sizes) {
            key.draw(
                at: NSPoint(x: x, y: floor((self.bounds.height - size.height) / 2)),
                withAttributes: attributes
            )
            x += size.width + spacing
        }
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
