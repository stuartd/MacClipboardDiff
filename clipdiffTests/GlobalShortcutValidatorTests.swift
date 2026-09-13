import AppKit
import Carbon
import XCTest
@testable import ClipDiffCore

@MainActor
final class GlobalShortcutValidatorTests: XCTestCase {
    func testOnlyEnabledExactSystemShortcutsConflict() async {
        let shortcut = GlobalShortcut.defaultShortcut
        var validator = validator()
        validator.systemShortcuts = {
            .success([.init(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers, isEnabled: true)])
        }
        XCTAssertEqual(validator.error(for: shortcut), .systemShortcut)
        validator.systemShortcuts = {
            .success([
                .init(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers, isEnabled: false),
                .init(keyCode: shortcut.keyCode, modifiers: UInt32(cmdKey), isEnabled: true),
                .init(keyCode: 8, modifiers: shortcut.carbonModifiers, isEnabled: true)
            ])
        }
        XCTAssertNil(validator.error(for: shortcut))
    }

    func testMenuCheckFindsDisabledNestedCommandUsingItsActualBinding() async {
        let menu = NSMenu()
        let submenu = NSMenu()
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        edit.submenu = submenu
        menu.addItem(edit)
        let copy = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "c")
        copy.isEnabled = false
        copy.keyEquivalentModifierMask = [.command]
        submenu.addItem(copy)
        let checker = validator(menu: menu)
        let commandC = GlobalShortcut(keyCode: 8, modifiers: [.command])!
        XCTAssertEqual(checker.error(for: commandC), .menuItem("Copy"))
        XCTAssertNil(checker.error(for: GlobalShortcut(keyCode: 8, modifiers: [.command, .option])!))

        // Read the live menu each time; do not keep a blacklist of familiar keys.
        copy.keyEquivalent = "d"
        XCTAssertNil(checker.error(for: commandC))
        XCTAssertEqual(checker.error(for: GlobalShortcut(keyCode: 2, modifiers: [.command])!), .menuItem("Copy"))
    }

    func testMenuCheckNormalizesImplicitShiftAndUsesKeyboardLayout() async {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Custom command", action: nil, keyEquivalent: "D")
        item.keyEquivalentModifierMask = [.command]
        menu.addItem(item)
        var checker = validator(menu: menu)
        // This layout puts D on the physical key normally labelled C.
        checker.characters = { _, shifted in shifted ? "D" : "d" }
        XCTAssertEqual(checker.error(for: GlobalShortcut(keyCode: 8, modifiers: [.command, .shift])!), .menuItem("Custom command"))
        XCTAssertNil(checker.error(for: GlobalShortcut(keyCode: 8, modifiers: [.command])!))
    }

    func testMenuCheckHandlesShiftedPunctuation() async {
        let menu = NSMenu()
        let help = NSMenuItem(title: "Help", action: nil, keyEquivalent: "?")
        help.keyEquivalentModifierMask = [.command]
        menu.addItem(help)
        var checker = validator(menu: menu)
        checker.characters = { _, shifted in shifted ? "?" : "/" }
        XCTAssertEqual(checker.error(for: GlobalShortcut(keyCode: 44, modifiers: [.command, .shift])!), .menuItem("Help"))
        XCTAssertNil(checker.error(for: GlobalShortcut(keyCode: 44, modifiers: [.command])!))
    }

    func testMissingMenuDoesNotInventCommandCConflict() async {
        XCTAssertNil(validator().error(for: GlobalShortcut(keyCode: 8, modifiers: [.command])!))
    }

    func testSystemQueryFailureIsReportedRatherThanCalledAConflict() async {
        var checker = validator()
        checker.systemShortcuts = { .failure(.systemCheckFailed(-108)) }
        XCTAssertEqual(checker.error(for: .defaultShortcut), .systemCheckFailed(-108))
    }

    func testMissingKeyboardLayoutIsReportedWhenCheckingMenus() async {
        var checker = validator(menu: NSMenu())
        checker.characters = { _, _ in nil }
        XCTAssertEqual(checker.error(for: .defaultShortcut), .keyboardLayoutUnavailable)
    }

    private func validator(menu: NSMenu? = nil) -> GlobalShortcutValidator {
        GlobalShortcutValidator(
            systemShortcuts: { .success([]) },
            mainMenu: { menu },
            characters: { shortcut, shifted in
                shifted ? shortcut.keyLabel : shortcut.keyLabel.lowercased()
            }
        )
    }
}
