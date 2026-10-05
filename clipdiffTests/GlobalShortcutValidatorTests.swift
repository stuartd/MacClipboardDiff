import AppKit
import Carbon
import XCTest
@testable import ClipDiffCore

@MainActor
final class GlobalShortcutValidatorTests: XCTestCase {
    func testCommandAndCommandShiftAreRejectedBeforeQueryingSystem() async throws {
        let checker = GlobalShortcutValidator(
            systemShortcuts: { .failure(.systemCheckFailed(-108)) }, mainMenu: { nil })
        for keyCode: UInt32 in [1, 8, 12, 44] {
            for modifiers: GlobalShortcut.Modifiers in [[.command], [.command, .shift]] {
                let shortcut = try XCTUnwrap(GlobalShortcut(keyCode: keyCode, modifiers: modifiers))
                XCTAssertEqual(checker.error(for: shortcut), .requiresOptionOrControl)
            }
        }
    }

    func testEveryCombinationContainingOptionOrControlIsAllowed() async throws {
        let checker = validator()
        for rawValue: UInt32 in 1...GlobalShortcut.Modifiers.supported.rawValue {
            let modifiers = GlobalShortcut.Modifiers(rawValue: rawValue)
            guard !modifiers.intersection([.option, .control]).isEmpty else { continue }
            let shortcut = try XCTUnwrap(GlobalShortcut(keyCode: 1, modifiers: modifiers))
            XCTAssertNil(checker.error(for: shortcut))
        }
        XCTAssertNil(checker.error(for: .defaultShortcut))
    }

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
                .init(keyCode: 2, modifiers: shortcut.carbonModifiers, isEnabled: true)
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
        copy.keyEquivalentModifierMask = [.command, .option]
        submenu.addItem(copy)
        let checker = validator(menu: menu)
        let optionCommandC = GlobalShortcut(keyCode: 8, modifiers: [.command, .option])!
        XCTAssertEqual(checker.error(for: optionCommandC), .menuItem("Copy"))
        XCTAssertNil(checker.error(for: GlobalShortcut(keyCode: 8, modifiers: [.command, .control])!))

        // Read the live menu each time; do not keep a blacklist of familiar keys.
        copy.keyEquivalent = "d"
        XCTAssertNil(checker.error(for: optionCommandC))
        XCTAssertEqual(checker.error(for: GlobalShortcut(keyCode: 2, modifiers: [.command, .option])!), .menuItem("Copy"))
    }

    func testMenuCheckNormalizesImplicitShiftAndUsesKeyboardLayout() async {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Custom command", action: nil, keyEquivalent: "D")
        item.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(item)
        var checker = validator(menu: menu)
        // This layout puts D on the physical key normally labelled C.
        checker.characters = { _, shifted in shifted ? "D" : "d" }
        XCTAssertEqual(checker.error(for: GlobalShortcut(keyCode: 8, modifiers: [.command, .control, .shift])!), .menuItem("Custom command"))
        XCTAssertNil(checker.error(for: GlobalShortcut(keyCode: 8, modifiers: [.command, .control])!))
    }

    func testMenuCheckHandlesShiftedPunctuation() async {
        let menu = NSMenu()
        let help = NSMenuItem(title: "Help", action: nil, keyEquivalent: "?")
        help.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(help)
        var checker = validator(menu: menu)
        checker.characters = { _, shifted in shifted ? "?" : "/" }
        XCTAssertEqual(checker.error(for: GlobalShortcut(keyCode: 44, modifiers: [.command, .control, .shift])!), .menuItem("Help"))
        XCTAssertNil(checker.error(for: GlobalShortcut(keyCode: 44, modifiers: [.command, .control])!))
    }

    func testMissingMenuAllowsOptionCommandC() async {
        XCTAssertNil(validator().error(for: GlobalShortcut(keyCode: 8, modifiers: [.command, .option])!))
    }

    func testShiftedPunctuationWithExplicitShiftAlsoConflicts() async {
        let menu = NSMenu()
        let help = NSMenuItem(title: "Help", action: nil, keyEquivalent: "?")
        help.keyEquivalentModifierMask = [.command, .control, .shift]
        menu.addItem(help)
        var checker = validator(menu: menu)
        checker.characters = { _, shifted in shifted ? "?" : "/" }
        XCTAssertEqual(checker.error(for: GlobalShortcut(keyCode: 44, modifiers: [.command, .control, .shift])!), .menuItem("Help"))
        XCTAssertNil(checker.error(for: GlobalShortcut(keyCode: 44, modifiers: [.command, .control])!))
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
