# ClipDiff macOS/Windows feature-gap report

## Scope and method

This report compares the current macOS repository with the Windows reference at
`/tmp/ClipboardDiff-reference`. It is a source review, not a claim that either UI
was manually exercised on its native operating system. The comparison uses the
checked-out implementations and tests, rather than treating either README as the
source of truth. The reviewed revisions are macOS
`fc96fffd867e889c8926aa4f2186fb7f7bd82d14` and Windows
`5f9230ab8fec8da76f82e3140e7b913b251704b6`.

> **Follow-up status:** the P0 privacy-marker gap identified below has since been
> addressed. The current macOS clipboard store rejects concealed and transient
> pasteboards before reading their text or file URLs. The historical comparison
> is retained to explain the reason for the change.

The two products now have unusually close core parity. Both keep two captures in
memory, ignore unsupported clipboard changes, accept identical consecutive
copies, remove a recently captured value after an explicit clear, support one or
two copied files with bounded decoding, disambiguate duplicate basenames, offer
side-by-side and unified views, copy a unified diff, permit a configurable global
shortcut, and support external viewers behind a one-time plaintext warning and
best-effort temporary-file cleanup.

Platform-specific names and mechanisms are not gaps by themselves: menu bar vs.
notification area, `Option-Command-D` vs. `Ctrl+Alt+D`, Finder Sync vs. Explorer
Shell integration, Launch Services vs. App Paths, and each platform's native
viewer catalog should remain native.

## Executive findings

1. **At the reviewed baseline, the most important macOS gap was privacy-intent
   screening before payload reads.** The follow-up implementation now checks
   concealed/transient markers before it reads either text or file paths.
2. **The clearest workflow gap on macOS is the missing one-file Finder action.**
   Windows can compare a selected file with the current capture; macOS Finder
   integration only accepts exactly two selected files.
3. **macOS has the better cold-start and paused-monitoring Finder workflow.** Its
   two-file command launches the containing app and direct pairs are intentionally
   independent of clipboard monitoring. Windows only exposes/accepts its pair
   command while the tray process is running and monitoring.
4. **The macOS Finder handoff exposes full paths in a custom URL.** The request is
   excluded from Recent Items, but Windows deliberately transports selection data
   through COM/local IPC instead of a command line or registry. This is a privacy
   hardening opportunity, not evidence that macOS currently persists paths.
5. Beyond these items, apparent differences are predominantly platform
   conventions or catalog coverage, not missing product capability.

## Capability matrix

| Capability | macOS | Windows | Assessment |
| --- | --- | --- | --- |
| Future-only, two-entry in-memory history | Yes: startup `changeCount` baseline and two-entry truncation (`clipdiff/ClipDiffController.swift:50`; `clipdiff/ClipboardHistory.swift:114-126`) | Yes: startup sequence baseline and bounded history (`src/ClipDiff.Core/ClipboardHistory.cs:14-19,165-181`) | Parity |
| Pause/resume without importing clipboard contents copied while paused | Yes (`clipdiff/ClipDiffController.swift:105-120`) | Yes (`src/ClipDiff.Windows/AppController.cs:152-160`) | Parity |
| Recent explicit-clear heuristic | Yes, 60 seconds (`clipdiff/ClipboardHistory.swift:3-4,141-153`) | Yes, 60 seconds (`src/ClipDiff.Core/ClipboardHistory.cs:3-5,241-254`) | Parity |
| Clipboard privacy-intent markers checked before payload | Yes after follow-up: concealed/transient marker names are inspected before either payload accessor (`clipdiff/ClipboardStore.swift`) | Yes: exclusion/history/cloud markers precede file/text reads (`src/ClipDiff.Windows/Clipboard/ClipboardPrivacyInspector.cs:43-94`) | Parity at the advisory-policy level |
| App's own copied diff excluded from capture | Yes: change count is baselined and an `ownWrite` observation is applied (`clipdiff/ClipDiffController.swift:270-285`) | Yes, with native exclusion markers and own-write suppression (`src/ClipDiff.Windows/AppController.cs:475-491`) | Functional parity; Windows conveys stronger intent to other monitors |
| One/two copied files, maximum 16 MiB, text/binary fallback | Yes (`clipdiff/ClipDiffController.swift:344-365`; `clipdiff/CopiedFileTextReader.swift`) | Yes (`src/ClipDiff.Windows/Clipboard/CopiedFileTextReader.cs`) | Parity |
| Exactly-two-file context action | Yes, Finder Sync (`ClipDiffFinderSync/FinderSyncExtension.swift:18-40,70-80`) | Yes, Explorer Shell extension (`src/ClipDiff.ShellExtension/ShellExtension.cpp`) | Parity at user level |
| Compare one selected file with existing current capture | No | Yes; it promotes the selected file to Current and opens the diff (`src/ClipDiff.Windows/AppController.cs:303-357`) | **Windows-only workflow** |
| Context comparison launches app if it is not running | Yes (`ClipDiffFinderSync/FinderSyncExtension.swift:43-60`) | No; readiness/registration is tied to a running, monitoring app (`src/ClipDiff.Windows/Explorer/ExplorerContextMenuRegistration.cs:60-124`) | **macOS-only workflow** |
| Direct two-file comparison while clipboard monitoring is paused | Yes: direct pair replacement does not require `isMonitoring`; this is covered by `clipdiffTests/ClipboardHistoryTests.swift:151-175` | No: selection is rejected unless monitoring is active (`src/ClipDiff.Windows/AppController.cs:380-387,405-409`) | **macOS-only behavior** |
| Path-minimizing integration transport | Partial: Recent Items are disabled, but file URL strings become custom-URL query items (`ClipDiffFinderSync/FinderSyncExtension.swift:43-55,83-92`) | Yes: pair selection is marshalled to the running process and the one-file path uses same-user/session IPC (`src/ClipDiff.Windows/Explorer/*`) | **Windows privacy advantage** |
| External viewers, custom executable, fallback | Yes (`clipdiff/ExternalDiffTool.swift`; `clipdiff/ClipDiffController.swift:128-184,233-258`) | Yes (`src/ClipDiff.Windows/ExternalDiff/*`; `src/ClipDiff.Windows/AppController.cs:228-287`) | Parity; catalogs appropriately differ |
| One-time external-viewer plaintext warning and cleanup | Yes (`clipdiff/ClipDiffController.swift:292-318`; `clipdiff/ExternalDiffWorkspace.swift`) | Yes (`src/ClipDiff.Windows/AppController.cs:443-473`; `src/ClipDiff.Windows/ExternalDiff/ExternalDiffWorkspace.cs`) | Parity |
| Reusable native diff window, side-by-side/unified, copy/clear | Yes (`clipdiff/DiffWindowController.swift`; `clipdiff/DiffWindowView.swift`) | Yes (`src/ClipDiff.Windows/Views/DiffWindow.xaml`; `src/ClipDiff.Windows/ViewModels/DiffWindowViewModel.cs`) | Parity |
| Explicit process single-instance guard | No app-owned guard found; normal Launch Services app activation is the macOS convention | Yes, named per-session mutex (`src/ClipDiff.Windows/App.xaml.cs:9-54`) | Platform implementation difference; no macOS feature request recommended |
| “Copy as path” recognition | Not implemented | Windows parses exactly one/two quoted absolute paths (`src/ClipDiff.Windows/Clipboard/ExplorerCopyAsPathParser.cs`) | Windows-specific convention; not a macOS gap |

## Features present on Windows but absent on macOS

### W1 — Privacy-intent formats before any payload read (addressed)

Windows first checks whether formats exist, then checks its monitor/history/cloud
exclusion formats, and only after that asks for file paths or Unicode text
(`ClipboardPrivacyInspector.cs:43-94`). Malformed marker data is treated
conservatively (`ClipboardPrivacyInspector.cs:102-110`). Its tests isolate this
policy in `ClipboardPrivacyInspectorTests.cs`.

At the reviewed revision, the macOS store instead invoked `readObjects` for file
URLs before inspecting any other type, then called `string(forType:)`. The
follow-up implementation introduces a metadata-first boundary and tests that
neither payload accessor is invoked for concealed or transient pasteboards.

**Recommendation:** add a pure, testable pasteboard privacy policy ahead of both
file and string reads. Recognize the macOS ecosystem's transient/concealed (and,
after compatibility research, auto-generated) pasteboard types by raw UTI name,
because AppKit does not expose all of them as strongly typed constants. Excluded
observations should leave history unchanged and cancel recent-clear eligibility,
just as an intervening privacy observation does on Windows. Do not infer secrets
from content, source application, length, entropy, or token-like syntax.

This should remain advisory and be documented as such: producer support is not
universal, Swift strings cannot be securely zeroed, and the system clipboard and
other clipboard monitors remain outside ClipDiff's control.

### W2 — Compare a single Finder file with the current capture

Windows dynamically provides **Compare with current ClipDiff capture** when a
current entry exists and monitoring is active. The selected file is read with the
same bounded reader, becomes Current, the former Current becomes Previous, and
the viewer opens without changing the clipboard (`AppController.cs:303-357`).

macOS Finder Sync only creates a menu for exactly two regular files
(`FinderSyncExtension.swift:18-40,70-80`), and the application request parser and
controller only accept pairs (`clipdiff/FinderComparisonRequest.swift`;
`ClipDiffController.swift:214-230`).

**Recommendation:** add the one-file action only after designing a minimal,
privacy-safe availability signal between the app and Finder extension. Preserve
the Windows semantics: require a current capture, use the bounded reader off the
main actor, revalidate state after the read, do not touch the pasteboard, and show
the same external-viewer warning/fallback. Do not persist capture text, full
source paths, or previews merely to let the extension decide menu visibility.
If a reliable state-only signal requires disproportionate machinery, an always
visible Finder command that fails clearly when no current capture exists is safer
than persisting sensitive state—but is less polished and should be validated
against Finder conventions first.

## Features present on macOS but absent on Windows

### M1 — Finder pair comparison can launch ClipDiff

The Finder extension opens the custom request with the containing application and
activates it (`FinderSyncExtension.swift:43-60`). Windows intentionally makes the
pair command available only while its readiness event says the running app is
monitoring. Consequently the macOS workflow works from a cold start while the
Windows workflow requires ClipDiff already running.

**Windows recommendation:** consider a cold-start pair command only if selection
paths can be transferred without placing them in a process command line, registry,
log, or durable queue. The current Windows design's privacy property is more
important than cold-start convenience; this is P3, not a parity mandate.

### M2 — Explicit Finder pair comparisons remain independent of monitoring

The macOS history permits explicit pair replacement while monitoring is paused,
and a focused test codifies it (`ClipboardHistoryTests.swift:151-175`). Windows
both hides and rejects pair comparisons while paused (`AppController.cs:380-387,
405-409`). The macOS behavior treats Pause as “stop observing the clipboard,” not
“disable user-invoked comparisons,” which is a clearer native mental model.

**Windows recommendation:** consider decoupling explicit Explorer commands from
clipboard monitoring. If Pause is deliberately intended as a global privacy
switch, retain current behavior but rename/explain it accordingly. No macOS
change is recommended.

### M3 — User-facing Finder extension management

macOS exposes **Enable Finder menu…** / enabled status and opens the system's
extension-management interface (`clipdiff/MenuContentView.swift:36-49`;
`ClipDiffController.swift:141-143,210-212`). Windows registers per-user Explorer
verbs directly and therefore has no exact equivalent. This is good macOS platform
integration, not a Windows deficiency requiring imitation.

## Privacy and architecture issue revealed by the comparison

The macOS extension serializes the two full file URLs as query items in a
`clipdiff://compare-selected-files` URL (`FinderSyncExtension.swift:83-92`). It
sets `addsToRecentItems = false`, which is important, and the app only retains
paths with its in-memory entries. Nevertheless, putting source paths in a URL
increases their exposure surface across application-launch plumbing. By contrast,
the Windows pair workflow passes a Shell data object directly to the running app,
and its single-file workflow uses a same-user/session pipe.

**Recommendation:** threat-model the Finder-to-app handoff and confirm with
instrumentation whether Launch Services, unified logging, crash reports, or other
OS components retain the request URL. If they do, replace it with a native,
ephemeral IPC/handoff that authenticates the bundled extension and never stores
the paths. Do not “fix” it with `UserDefaults`, an App Group file, a distributed
notification carrying paths, or another durable queue. Until evidence establishes
actual retention, describe this as hardening rather than a privacy defect.

## Prioritised recommendations

| Priority | Target | Recommendation | Why now / acceptance boundary |
| --- | --- | --- | --- |
| **Completed** | macOS | Screen supported transient/concealed privacy-intent pasteboard types before reading file URLs or text. | Implemented with payload-access fakes proving excluded text and file URLs are not read. |
| **P1** | macOS | Threat-model and, if retention is demonstrated, replace the full-path custom-URL Finder handoff with authenticated ephemeral IPC. | Paths are sensitive metadata. Preserve cold-start behavior only if it can be achieved without durable path storage. |
| **P2** | macOS | Add **Compare with current ClipDiff capture** for one regular Finder file. | High workflow value and established Windows behavior, but state signalling must not compromise privacy or make the small app into a service. |
| **P3** | Windows | Allow explicit two-file Explorer comparisons while clipboard monitoring is paused, or clarify that Pause is a global privacy switch. | Improves semantic clarity; no effect on macOS implementation. |
| **P3** | Windows | Explore privacy-preserving cold-start Explorer pair comparison. | Convenience only; reject designs that expose paths in command lines or durable storage. |
| **No action** | Both | Force identical viewer catalogs, shortcut syntax, startup controls, context-menu technology, or explicit process guards. | These are platform conventions. Maintain equivalent outcomes, not identical implementation. |

## Suggested macOS sequencing (no application changes in this report)

1. Keep the completed pasteboard-marker policy covered by payload-access tests
   and include it in manual privacy checks.
2. Instrument the Finder request transport with synthetic, non-sensitive paths;
   do not log real selected paths. Decide whether replacement IPC is necessary.
3. Design the one-file Finder action around an in-memory current capture and
   revalidation after asynchronous reads. Keep the existing two-entry model.
4. Run `swift test`, build a local Release app, and perform the privacy, paused
   monitoring, copied-file, Finder, external-viewer, and clear-history smoke tests
   on macOS before shipping.

## Explicit non-recommendations

- Do not persist clipboard contents, previews, diffs, or source paths to obtain
  cross-process feature parity.
- Do not add cloud sync, accounts, a document library, onboarding, analytics,
  automatic updates, or a general settings surface.
- Do not copy Windows registry, named-mutex, clipboard-retry, or Shell-extension
  mechanisms onto macOS when AppKit/Launch Services/Finder conventions already
  provide the appropriate outcome.
- Do not auto-launch an external viewer without the existing explicit selection,
  one-time plaintext warning, read-only temporary files, and best-effort cleanup.
- Do not treat OS-specific external-tool catalog entries as product gaps.
