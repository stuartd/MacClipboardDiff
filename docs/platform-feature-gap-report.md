# ClipDiff macOS/Windows feature-gap report

## Implementation status — 13 September 2026

This report compares the current macOS implementation at
`31f3499f916e61221e1938545403e9cc56072ba5` with the Windows reference revision
`5f9230ab8fec8da76f82e3140e7b913b251704b6`. It is a source-and-test review, not
a claim that either interface was manually exercised on its native operating
system.

The two gaps originally identified by this report are now closed on macOS:
ClipDiff screens concealed and transient pasteboard types before reading their
payloads, and its Finder extension can compare one selected regular file with the
current in-memory capture. The remaining differences are platform conventions or
privacy-hardening opportunities rather than missing core workflow.

## Shared capabilities

Both applications:

- retain only the two most recent captures in memory and start from a clipboard
  change-count baseline;
- ignore unsupported changes, retain identical consecutive copies as distinct
  captures, and apply a 60-second recent-clear privacy heuristic;
- compare plain text and one or two copied files, with bounded decoding and
  filename-and-reason fallbacks for unusable files;
- disambiguate duplicate basenames and offer side-by-side and unified native
  views, unified-diff copying, and a configurable global shortcut;
- support external viewers behind a one-time plaintext warning, read-only
  temporary files, launch fallback, and best-effort cleanup; and
- provide native file-manager commands for comparing exactly two selected regular
  files and for comparing one selected regular file with the current capture.

Platform-specific mechanisms are intentionally different: macOS uses a menu bar
extra, `Option-Command-D`, Finder Sync, and Launch Services, while Windows uses a
notification-area app, `Ctrl+Alt+D`, Explorer integration, and Windows-native
application discovery.

## Capability matrix

| Capability | macOS | Windows | Assessment |
| --- | --- | --- | --- |
| Future-only, two-entry in-memory history | Startup `changeCount` baseline and bounded history | Startup sequence baseline and bounded history | Parity |
| Pause/resume without importing clipboard contents copied while paused | Yes | Yes | Parity |
| Recent explicit-clear heuristic | Yes, 60 seconds | Yes, 60 seconds | Parity |
| Privacy-intent markers checked before payload reads | Concealed and transient pasteboard types are checked before file URLs or strings | Exclusion, history, and cloud markers are checked before file paths or text | Functional parity for each platform's established markers |
| App's copied diff excluded from capture | Own-write observation and change-count baseline | Native exclusion markers and own-write suppression | Functional parity; Windows also signals intent to other monitors |
| One/two copied files, maximum 16 MiB, text/binary fallback | Yes | Yes | Parity |
| Compare exactly two selected files | Finder Sync; works on cold start and while monitoring is paused | Explorer integration; requires the running app and active monitoring | Core parity; macOS has the more flexible lifecycle |
| Compare one selected file with the current capture | Finder action uses the retained capture, does not change the clipboard, and works while paused | Explorer action uses the retained capture while monitoring | Core parity; availability/lifecycle follows platform integration |
| Path-minimizing integration transport | Full file URL strings are encoded in a custom URL, with Recent Items disabled | Same-user/session IPC avoids command-line and registry transport | Windows privacy advantage; macOS hardening opportunity |
| External viewers, custom executable, and fallback | Yes, with a macOS-native catalog | Yes, with a Windows-native catalog | Parity |
| Reusable native diff window, side-by-side/unified, copy/clear | Yes | Yes | Parity |
| Explicit process single-instance guard | No app-owned guard; normal Launch Services activation | Named per-session mutex | Platform implementation difference |
| “Copy as path” recognition | Copied absolute text paths are resolved as files | Quoted Explorer “Copy as path” values are parsed | Equivalent platform-appropriate workflow |

## Current macOS behavior

### Pasteboard privacy markers

`SystemClipboardStore` reads the pasteboard's type identifiers first. If either
`org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType` is present,
it returns a non-text observation without asking AppKit to materialize file URLs
or text. This policy is covered with a fake pasteboard, including marker
precedence over payload reads.

These markers remain advisory: producer support is not universal, unmarked
secrets are indistinguishable from ordinary text, Swift strings cannot be
securely zeroed, and operating-system paging and other clipboard monitors remain
outside ClipDiff's control.

### Finder comparisons

With one regular file selected, Finder offers **Compare with current ClipDiff
capture**. The app preserves the captured entry as Previous, reads the selected
file asynchronously as Current, and uses the configured viewer without touching
the clipboard. A retained capture works while monitoring is paused. With no
capture—including a cold start—the app activates and displays an explanatory
message without reading the selected file.

With exactly two regular files selected, Finder offers **Compare two selected
files with ClipDiff**. This direct comparison replaces the in-memory pair and
works on cold start or while monitoring is paused. Zero, more than two, or any
folder or non-regular selection offers neither command.

Delayed reads are guarded against stale request and capture identity. A newer
Finder request, monitored pasteboard change, clear, diff copy, or monitoring
transition cancels or invalidates a pending one-file comparison. Clipboard
changes while monitoring remains paused do not invalidate the explicit request.

## Remaining privacy-hardening opportunity

The Finder extension encodes selected full file URLs as query items in a
`clipdiff://` request. It disables Recent Items, validates the operation and file
arity in both processes, and does not persist the request, captures, or source
paths. Nevertheless, a URL broadens the metadata exposure surface across the
application-launch path compared with Windows' same-user/session IPC.

Threat-model and instrument this handoff using synthetic, non-sensitive paths. If
Launch Services, unified logging, crash reports, or another OS component retains
the request, replace it with authenticated ephemeral IPC. Do not replace it with
`UserDefaults`, an App Group file, a distributed notification containing paths,
or another durable queue. Preserve cold-start pair comparison only if that can be
done without durable path storage.

## Prioritised recommendations

| Priority | Target | Recommendation | Acceptance boundary |
| --- | --- | --- | --- |
| **P1** | macOS | Verify whether the full-path custom-URL Finder handoff is retained and replace it with authenticated ephemeral IPC if necessary. | Never use real user paths for instrumentation or introduce durable path storage. |
| **P3** | Windows | Allow explicit Explorer comparisons while clipboard monitoring is paused, or clarify that Pause is a global privacy switch. | Keep clipboard monitoring and deliberate file comparisons conceptually distinct. |
| **P3** | Windows | Explore privacy-preserving cold-start Explorer pair comparison. | Do not expose paths in command lines, the registry, logs, or a durable queue. |
| **No action** | Both | Force identical viewer catalogs, shortcut syntax, startup controls, context-menu technology, or process guards. | Preserve equivalent outcomes while following native platform conventions. |

## Explicit non-recommendations

- Do not persist clipboard contents, previews, diffs, or source paths for
  cross-process feature parity.
- Do not add cloud sync, accounts, a document library, onboarding, analytics,
  automatic updates, or a general settings surface.
- Do not copy Windows registry, named-mutex, clipboard-retry, or Shell-extension
  mechanisms onto macOS when AppKit, Launch Services, and Finder conventions
  already provide the appropriate outcome.
- Do not auto-launch an external viewer without explicit selection, the existing
  one-time plaintext warning, read-only temporary files, and best-effort cleanup.
- Do not treat OS-specific external-tool catalog entries as product gaps.
