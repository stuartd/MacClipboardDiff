# ClipDiff

ClipDiff is a tiny macOS menu bar utility for comparing the last two copied text values.

## Run It


```sh
scripts/create-local-release.sh
```

The app is copied to `releases/ClipDiff.app` and opened.

## Workflow

1. Copy the older text.
2. Copy the newer text.
3. Press `Option-Command-D`, or choose **Show Diff** from the menu bar item.
4. View the diff in a native window.

## Design

- The app monitors the pasteboard through [`NSPasteboard`](https://developer.apple.com/documentation/appkit/nspasteboard), using `changeCount` to detect updates.
- Only plain text clipboard values are captured.
- Duplicate consecutive values are ignored.
- Non-text clipboard values are ignored.
- Captured text is kept in memory only.
- The diff view is internal SwiftUI UI, not Terminal output.

## Diff View

The default view is side-by-side:

- previous clipboard text on the left
- current clipboard text on the right
- changed and removed lines tinted red
- changed and added lines tinted green

There is also a unified view for copying or scanning a compact diff.

## Tests

The core clipboard-history and diff behavior is covered by SwiftPM XCTest tests:

```sh
swift test
```
