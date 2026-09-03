import Foundation
import XCTest
@testable import ClipDiffCore

final class GlobalShortcutTests: XCTestCase {
    func testDefaultShortcutIsOptionCommandD() {
        XCTAssertEqual(GlobalShortcut.defaultShortcut.displayString, "⌥⌘D")
        XCTAssertEqual(GlobalShortcut.defaultShortcut.keyCode, 2)
        XCTAssertEqual(GlobalShortcut.defaultShortcut.modifiers, [.command, .option])
    }

    func testShortcutRequiresCommandOptionOrControl() {
        XCTAssertNil(GlobalShortcut(keyCode: 0, modifiers: []))
        XCTAssertNil(GlobalShortcut(keyCode: 0, modifiers: [.shift]))
        XCTAssertNotNil(GlobalShortcut(keyCode: 0, modifiers: [.control]))
    }

    func testShortcutRejectsUnsupportedKeysAndModifierBits() {
        XCTAssertNil(GlobalShortcut(keyCode: 49, modifiers: [.command]))
        XCTAssertNil(GlobalShortcut(
            keyCode: 0,
            modifiers: GlobalShortcut.Modifiers(rawValue: 1 << 12)
        ))
    }

    func testSettingsRoundTrip() throws {
        let suiteName = "ClipDiffTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = GlobalShortcutSettingsStore(defaults: defaults)
        let shortcut = try XCTUnwrap(GlobalShortcut(
            keyCode: 8,
            modifiers: [.command, .control, .shift]
        ))

        store.save(shortcut)

        XCTAssertEqual(store.load(), shortcut)
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("GlobalShortcut.")
        }.sorted(), [
            "GlobalShortcut.KeyCode",
            "GlobalShortcut.Modifiers"
        ])
    }

    func testSettingsUseDefaultForMissingOrInvalidValues() throws {
        let suiteName = "ClipDiffTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = GlobalShortcutSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), .defaultShortcut)

        defaults.set(999, forKey: "GlobalShortcut.KeyCode")
        defaults.set(0, forKey: "GlobalShortcut.Modifiers")
        XCTAssertEqual(store.load(), .defaultShortcut)

        defaults.set(-1, forKey: "GlobalShortcut.KeyCode")
        defaults.set(-1, forKey: "GlobalShortcut.Modifiers")
        XCTAssertEqual(store.load(), .defaultShortcut)
    }
}
