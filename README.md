# MacClipboardDiff

MacClipboardDiff is a tiny macOS menu bar utility for comparing the last two copied text values or text files.

## Run It

```sh
scripts/create-local-release.sh
```

The app is copied to `releases/MacClipboardDiff.app` and opened.

## Workflow

1. Copy the older text or file.
2. Copy the newer text or file.
3. Press `Option-Command-D`, or choose **Show Diff** from the menu bar item.
4. View the diff in the selected viewer. The built-in native window remains the default.

You can also copy exactly two files together in Finder. MacClipboardDiff immediately treats the first file as **Previous** and the second as **Current**.

## Copied Files

Finder file URLs take precedence over incidental path text on the pasteboard. A single copied file becomes one capture; exactly two copied files atomically replace the comparison pair; copies containing more than two files are ignored.

For a usable text file, MacClipboardDiff reads and retains the complete decoded contents in memory. It supports UTF-8, BOM-marked UTF-16 and UTF-32, common BOM-less UTF-16, and Windows-1252. Files larger than 16 MiB are not read.

An unusable file contributes its filename followed by a reason:

- `(binary file)`
- `(directory)`
- `(empty file)`
- `(file not found)`
- `(file unreadable)`
- `(file too large)`

The source filename is shown in menu previews, side-by-side headings, and unified diff headers. When both files have the same basename, MacClipboardDiff adds only enough parent directories to distinguish them, such as `branch-a/Sources/settings.json` and `branch-b/Sources/settings.json`.

The full standardized file path is retained only with the corresponding in-memory history entry. A generated diff keeps its resolved display label but drops the full path. File contents and paths are never logged, uploaded, indexed, or persisted.

## Design

- The app monitors `NSPasteboard.changeCount` and captures only future changes.
- Plain text and one or two copied file URLs are supported.
- Separate copy events are captured even when their text is identical.
- Unsupported non-text changes are ignored without clearing history.
- A copied value immediately followed by an explicit clipboard clear within 60 seconds is removed as a best-effort privacy measure.
- Captured content is kept in memory only and lost when the app exits.
- Slow file reads are superseded if a newer pasteboard change arrives.
- The built-in diff is native SwiftUI and never writes captured text to disk.

## External Diff Viewers

The menu's **Diff viewer** submenu lists supported applications found on the Mac, provides **Choose Application…** for another app or executable, and lets you return to the built-in viewer. The selection is remembered.

MacClipboardDiff recognizes these viewer profiles:

- FileMerge
- Kaleidoscope
- Beyond Compare
- Araxis Merge
- Visual Studio Code
- Cursor
- BBEdit
- KDiff3
- Meld
- P4Merge
- SourceGear DiffMerge

The app checks Launch Services, `/Applications`, `~/Applications`, common Homebrew command locations, and its process `PATH`. A manually selected unknown executable receives the previous and current file paths as two separate positional arguments. If a selected viewer is missing or cannot be launched, **Show Diff** falls back to the built-in viewer without discarding either capture.

Known profiles use their supported wait, read-only, diff, and side-label options. File-backed captures preserve their basenames in separate **Previous** and **Current** directories, while viewers with title support receive the same disambiguated labels as the built-in diff.

The local build is not App Sandbox-restricted because it must start the explicitly selected external executable. The app remains dependency-free and does not add network access or broaden its clipboard and copied-file workflow.

## Diff View

The default view is side-by-side:

- previous text on the left
- current text on the right
- changed and removed lines tinted red
- changed and added lines tinted green

There is also a unified view for copying or scanning a compact diff. Diff rows are rendered lazily so larger text files do not eagerly construct every visible row.

## Privacy Limitations

The recent-clear behavior is only a heuristic. An unmarked secret is otherwise indistinguishable from ordinary text, and Swift strings cannot be guaranteed to be securely zeroed. Operating-system paging, process dumps, other clipboard monitors, and macOS clipboard behavior are outside MacClipboardDiff's control.

The built-in viewer keeps the memory-only privacy model. Selecting an external viewer creates an explicit exception because another application cannot compare the captured strings directly. Before the first external comparison, MacClipboardDiff warns that clipboard text may contain secrets and asks for confirmation. Cancelling opens the built-in viewer and creates no files.

After confirmation, each comparison writes two read-only UTF-8 plaintext files to a unique directory below the system temporary directory. MacClipboardDiff attempts to delete that directory after the launched comparison process exits, when MacClipboardDiff exits, and on its next launch. Cleanup is best effort: a crash, power loss, open file handle, or external application may leave or retain a copy. Do not select an external viewer when that disk exposure is unacceptable.

Only the selected executable path and the one-time warning acknowledgement are stored in app preferences. Clipboard text, previews, diffs, and source paths are never stored there.

## Tests

The SwiftPM XCTest suite covers clipboard history, recent clears, copied-file decoding and fallback behavior, filename disambiguation, version formatting, and line-based diff behavior:

```sh
swift test
```
