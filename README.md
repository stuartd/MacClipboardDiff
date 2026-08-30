# ClipDiff

ClipDiff is a tiny macOS menu bar utility for comparing the last two copied text values or text files.

## Run It

```sh
scripts/create-local-release.sh
```

The app is copied to `releases/ClipDiff.app` and opened.

## Workflow

1. Copy the older text or file.
2. Copy the newer text or file.
3. Press `Option-Command-D`, or choose **Show Diff** from the menu bar item.
4. View the diff in a native window.

You can also copy exactly two files together in Finder. ClipDiff immediately treats the first file as **Previous** and the second as **Current**.

## Copied Files

Finder file URLs take precedence over incidental path text on the pasteboard. A single copied file becomes one capture; exactly two copied files atomically replace the comparison pair; copies containing more than two files are ignored.

For a usable text file, ClipDiff reads and retains the complete decoded contents in memory. It supports UTF-8, BOM-marked UTF-16 and UTF-32, common BOM-less UTF-16, and Windows-1252. Files larger than 16 MiB are not read.

An unusable file contributes its filename followed by a reason:

- `(binary file)`
- `(directory)`
- `(empty file)`
- `(file not found)`
- `(file unreadable)`
- `(file too large)`

The source filename is shown in menu previews, side-by-side headings, and unified diff headers. When both files have the same basename, ClipDiff adds only enough parent directories to distinguish them, such as `branch-a/Sources/settings.json` and `branch-b/Sources/settings.json`.

The full standardized file path is retained only with the corresponding in-memory history entry. A generated diff keeps its resolved display label but drops the full path. File contents and paths are never logged, uploaded, indexed, or persisted.

## Design

- The app monitors `NSPasteboard.changeCount` and captures only future changes.
- Plain text and one or two copied file URLs are supported.
- Separate copy events are captured even when their text is identical.
- Unsupported non-text changes are ignored without clearing history.
- A copied value immediately followed by an explicit clipboard clear within 60 seconds is removed as a best-effort privacy measure.
- Captured content is kept in memory only and lost when the app exits.
- Slow file reads are superseded if a newer pasteboard change arrives.
- The built-in diff is native SwiftUI; no temporary files or external diff processes are used.

## Diff View

The default view is side-by-side:

- previous text on the left
- current text on the right
- changed and removed lines tinted red
- changed and added lines tinted green

There is also a unified view for copying or scanning a compact diff. Diff rows are rendered lazily so larger text files do not eagerly construct every visible row.

## Privacy Limitations

The recent-clear behavior is only a heuristic. An unmarked secret is otherwise indistinguishable from ordinary text, and Swift strings cannot be guaranteed to be securely zeroed. Operating-system paging, process dumps, other clipboard monitors, and macOS clipboard behavior are outside ClipDiff's control.

ClipDiff intentionally has no external-viewer integration because that would require writing captured values to temporary plaintext files.

## Tests

The SwiftPM XCTest suite covers clipboard history, recent clears, copied-file decoding and fallback behavior, filename disambiguation, version formatting, and line-based diff behavior:

```sh
swift test
```
