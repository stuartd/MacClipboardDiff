# Agent Guide

## Project Context

ClipDiff is a tiny native macOS menu bar utility for comparing the last two copied plain-text or text-file values.

Keep it small. This is not an App Store product, not a cloud service, and not a document-management app. The ideal workflow is: copy older text or a text file, copy newer text or a text file, press `Option-Command-D` or choose **Show Diff**, then read or copy the diff.

## Repository Map

- `clipdiff/clipdiffApp.swift`: SwiftUI app entry point and menu bar extra.
- `clipdiff/ClipDiffController.swift`: clipboard polling, in-memory capture state, diff creation, hotkey action, and window coordination.
- `clipdiff/ClipboardHistory.swift`: in-memory clipboard capture policy and testable history behavior.
- `clipdiff/ClipboardObservation.swift`: typed clipboard snapshots and history observations.
- `clipdiff/ClipboardStore.swift`: pasteboard access protocol plus the `NSPasteboard` implementation.
- `clipdiff/CopiedFileTextReader.swift`: bounded, testable text-file decoding and fallback behavior.
- `clipdiff/MenuContentView.swift`: menu bar popover content and commands.
- `clipdiff/HotKeyController.swift`: Carbon global hotkey registration for `Option-Command-D`.
- `clipdiff/GlobalShortcut.swift`: validated shortcut model and preferences persistence.
- `clipdiff/ShortcutSettingsWindowController.swift`: native global-shortcut recorder window.
- `clipdiff/ClipDiffApplicationDelegate.swift`: routes files opened by the Finder extension into the controller.
- `clipdiff/DiffEngine.swift`: text splitting, diff row generation, summaries, and copyable unified diff output.
- `clipdiff/ClipboardModels.swift`: clipboard entry, diff row/document, summary, view mode, and text-line models.
- `clipdiff/DiffWindowController.swift`: AppKit window wrapper for the SwiftUI diff view.
- `clipdiff/DiffWindowView.swift`: side-by-side and unified diff UI.
- `clipdiff/AppAbout.swift`: native About panel presentation.
- `clipdiff/AppVersionFormatter.swift`: version/build/commit display formatting.
- `clipdiff/Assets.xcassets/`: app icon and accent color assets.
- `ClipDiffFinderSync/`: Finder Sync extension that offers a comparison command for exactly two selected regular files.
- `ClipDiff-Info.plist`: generated bundle metadata inputs, including the release commit value.
- `Package.swift`: SwiftPM manifest used for focused core tests.
- `clipdiffTests/`: XCTest coverage for clipboard history and diff behavior.
- `scripts/create-local-release.sh`: builds and opens a local Release app at `releases/ClipDiff.app`.
- `scripts/_common.sh`: shared script constants.

## Build And Run

Create and open a local Release build:

```bash
scripts/create-local-release.sh
```

The built app is copied to `releases/ClipDiff.app`. `releases/` is intentionally ignored by git.

You can also run from Xcode:

```bash
open clipdiff.xcodeproj
```

Select the `clipdiff` scheme, choose **My Mac**, and press `Cmd-R`.

## Coding Guidelines

- Keep the app native: Swift, SwiftUI, AppKit, Carbon hotkeys, Foundation, and `NSPasteboard`.
- Preserve the in-memory privacy model. Captured text, decoded file contents, and source paths should not be written to disk, uploaded, logged, indexed, or retained after quitting.
- Capture plain text plus one or two copied file URLs. Treat separate copy events as separate entries even when their text is identical, and continue ignoring unsupported non-text clipboard changes.
- Keep full source paths only on the corresponding two-entry history. Resolve display labels before creating a diff document, then drop the paths from that document.
- Keep copied-file reads bounded, off the main actor, and superseded by newer pasteboard changes.
- Keep the main surface as a menu bar extra plus one diff window. Avoid settings screens, onboarding, accounts, sync, or background services unless explicitly requested.
- Keep `ClipDiffController` on the main actor. It touches pasteboard state, timers, window state, and SwiftUI-observed properties.
- Keep diff logic in `DiffEngine` and models in `ClipboardModels.swift`; do not bury diff behavior inside SwiftUI views.
- Keep clipboard capture policy in `ClipboardHistory`, file conversion in `CopiedFileTextReader`, and pasteboard access behind `ClipboardStore`.
- Keep views simple and inspectable. Side-by-side and unified modes should remain native SwiftUI views, not Terminal output or web content.
- Be careful with the global shortcut. If `Option-Command-D` cannot be registered, the menu command should still work.
- Do not add dependencies for this app unless there is a strong reason. The current implementation is intentionally dependency-free.

## Testing And Verification

Run the SwiftPM XCTest suite for core clipboard-history and diff behavior:

```bash
swift test
```

Use fakes for clipboard behavior in unit tests. Do not test `NSPasteboard.general`, AppKit windows, timers, or Carbon global hotkeys directly unless you are deliberately adding a small integration test.

For non-trivial logic changes, add focused tests around `ClipboardHistory`, `CopiedFileTextReader`, `ClipboardEntryDisplay`, `DiffEngine`, and pure model behavior.

Manual smoke test after changes:

1. Run `scripts/create-local-release.sh`.
2. Copy one plain-text value.
3. Copy another plain-text value, which may be identical when verifying that there are no changes.
4. Press `Option-Command-D`, or choose **Show Diff** from the menu bar item.
5. Check side-by-side and unified views.
6. Use **Copy diff** and confirm the clipboard receives unified diff text.
7. Use **Clear Captured Text** and confirm the app asks for two values again.
8. Copy one text file, then another, and verify filenames appear in both diff modes.
9. Copy exactly two text files together and verify their Finder order becomes previous/current.
10. Copy a binary, empty, directory, and oversized file and verify the fallback reason.
11. Change the global shortcut, verify the new shortcut works and the old one does not, then restore the default.
12. Enable the Finder extension, select exactly two regular files, and verify **Compare two selected files with ClipDiff** opens their diff. Verify the command is absent for other selection counts and folders, and that non-text files use the bounded reader's fallback reason after the command is chosen.

For pure diff changes, verify added, removed, changed, unchanged, blank-line, and trailing-newline cases.

## Release Notes For Agents

- Avoid committing generated output such as `releases/`, `.DS_Store`, derived data, or local Xcode user state.
- Root documentation files such as this one do not need to be added to the Xcode project.
- Scripts use bash with `set -euo pipefail`; keep script changes compatible with `scripts/_common.sh`.
- This project is for local builds. Do not add App Store, notarization, TestFlight, analytics, or packaging machinery unless the user explicitly asks.
