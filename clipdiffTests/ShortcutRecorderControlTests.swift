import AppKit
import XCTest
@testable import ClipDiffCore

// Small AppKit integration tests: isolated, invisible windows and synthetic events.
// No real pasteboard, event loop, or global hotkey registration is used.
@MainActor
final class ShortcutRecorderControlTests: XCTestCase {
    func testKeyEquivalentRecordsOnlyWhileRecorderHasFocus() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView()
        let recorder = ShortcutRecorderControl()
        let other = FocusTarget()
        content.addSubview(recorder)
        content.addSubview(other)
        window.contentView = content
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12
        ))
        var recordings: [GlobalShortcut] = []
        recorder.onChange = { recordings.append($0) }

        XCTAssertTrue(window.makeFirstResponder(other))
        XCTAssertFalse(recorder.performKeyEquivalent(with: event))
        XCTAssertTrue(recordings.isEmpty)

        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(recorder.performKeyEquivalent(with: event))
        XCTAssertEqual(recordings, [GlobalShortcut(keyCode: 12, modifiers: [.command])!])

        // Carbon consumes the currently registered key before AppKit sees it.
        // The global callback can feed that key back to the focused recorder.
        XCTAssertTrue(recorder.record(.defaultShortcut))
        XCTAssertEqual(recordings.last, .defaultShortcut)
        XCTAssertTrue(window.makeFirstResponder(other))
        XCTAssertFalse(recorder.record(.defaultShortcut))
        XCTAssertEqual(recordings.count, 2)
    }
}

private final class FocusTarget: NSView {
    override var acceptsFirstResponder: Bool { true }
}
