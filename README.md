# ClipDiff

ClipDiff is a tiny macOS menu bar utility for comparing the last two copied text values.

## Workflow

1. Copy the older text.
2. Copy the newer text.
3. Press `Option-Command-D`, or choose **Show Diff** from the menu bar item.
4. Read the diff in a native window.

## Design

- The app watches `NSPasteboard.general.changeCount`.
- Only plain text clipboard values are captured.
- Duplicate consecutive values are ignored.
- Non-text clipboard changes are ignored.
- Captured text is kept in memory only.
- The diff view is internal SwiftUI UI, not Terminal output.

## Diff View

The default view is side-by-side:

- previous clipboard text on the left
- current clipboard text on the right
- changed and removed lines tinted red
- changed and added lines tinted green

There is also a unified view for copying or scanning a compact diff.
