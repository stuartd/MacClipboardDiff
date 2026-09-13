# MacClipboardDiff: compare one Finder file with the current capture

## Cloud task

Implement this feature in `stuartd/MacClipboardDiff`, including focused tests and
documentation. Read `AGENTS.md` and the relevant code first. Use current `main`;
this specification was checked against `9cde6f9f043ad9a172a13ff4e375fe329caac471`
on 12 September 2026, after the concealed/transient pasteboard change merged.

This task covers one Finder action. The broader platform feature-gap report is
background, not an instruction to implement its remaining recommendations.

## User workflow

1. Copy text or a file while ClipDiff is monitoring, creating a capture.
2. Select one other regular file in Finder, potentially in a different folder.
3. Choose **Compare with current ClipDiff capture** from its contextual menu.
4. ClipDiff compares its existing capture on the left with the selected file on
   the right, using the configured diff viewer.

For example, capture `old/settings.json`, then invoke this action on
`new/settings.json`. The captured old contents become **Previous** and the
selected file's contents become **Current**. If the old file has since changed
on disk, use the captured contents; do not reread it.

The action does not change the system clipboard. A later, explicit **Copy diff**
still behaves normally.

## Finder menu and availability

| Selection | Finder command |
| --- | --- |
| Exactly one regular file | **Compare with current ClipDiff capture** |
| Exactly two regular files | Existing **Compare two selected files with ClipDiff** |
| Zero, more than two, or any folder/non-regular item | Neither command |

Inspect selection metadata to build the menu; read file contents only after the
user invokes the action. Recheck the selection when the command is invoked.
Keep binary files eligible, consistent with the existing two-file action.

For this version, the one-file command is available based on selection alone.
The app checks whether it has a current capture when it receives the request.
There is no new app-to-extension availability signal or shared capture state.

If there is no current capture, activate ClipDiff and show a brief native message:
**“Copy some text or a file while ClipDiff is monitoring, then try again.”**
The message must be visible from the Finder workflow, not only stored in a hidden
menu error. Leave history unchanged and do not read the selected file's contents.

The existing handoff may launch ClipDiff. A fresh process has no captures, so the
one-file action then shows that message. Never import the current pasteboard to
manufacture a starting capture. The existing two-file cold-start action continues
to work.

**Paused monitoring does not disable explicit Finder comparisons.** A one-file
comparison works while paused if a capture remains in memory. It leaves monitoring
paused. This follows the Mac app's existing two-file behavior.

## Comparison and history behavior

- Read the selected file asynchronously with `CopiedFileTextReader`, retaining
  its current 16 MiB limit, decoding rules and filename-and-reason fallbacks.
  Binary, empty, oversized, unreadable or vanished files use those fallbacks.
  Reject known directories and special files before attempting a content read.
- At request acceptance, identify the current history entry. On success, move
  that same entry to Previous, preserving its identity, capture time and source
  metadata. Insert the selected-file result as a new Current entry. Discard any
  older Previous entry; history still contains at most two entries.
- Commit the pair atomically on the main actor. Identical contents are a valid
  comparison and should display **No differences**.
- Cancel recent-clear eligibility on successful insertion, as for an explicit
  two-file comparison. A subsequent clipboard clear must not remove this direct
  Finder result through the recent-copy heuristic.
- Use existing filename disambiguation and the normal `showDiff` viewer flow,
  including the external-viewer warning, temporary-file cleanup and built-in
  fallback. Do not add a separate diff window or viewer path.
- A failed or discarded request must not partially update history or replace the
  displayed diff. Release its pending references when it finishes or is cancelled.

## Reads that finish after state changes

“Current capture” means the entry present when the app accepts the request. Never
silently substitute a newer entry when the file read completes.

Use a request generation/token and the expected current-entry ID, or an equally
small equivalent. The completion must still belong to the active request and the
same current entry before it can mutate history or open a viewer. Prefer retaining
the entry ID during the read and obtaining the entry from history at commit time.

Required behavior:

- A newly accepted one-file or two-file Finder request supersedes an older pending
  Finder read. Cancel any pending clipboard-file read when accepting the explicit
  request, following the existing pair workflow.
- **Clear Captured Text**, **Copy diff**, or a pause/resume transition cancels the
  pending one-file request. A late completion cannot restore cleared text or open
  an obsolete comparison.
- While monitoring is active, a newer pasteboard change invalidates the pending
  one-file request, even if the new item is ignored by capture policy. Check the
  change count again at completion to cover changes not yet seen by the timer.
  Continue normal privacy-screened clipboard processing.
- While monitoring stays paused, clipboard changes do not invalidate the request:
  the user deliberately selected an existing retained capture.
- Distinct captures with identical text are still different entries. Text equality
  is insufficient to decide that the original capture is unchanged.

When superseded, discard the result quietly; do not overwrite newer errors or
state. These rules require production guards as well as task cancellation.

## Request routing and privacy

Extend the existing Finder URL handoff with an explicit one-file operation, for
example `clipdiff://compare-with-current?file=<encoded-file-URL>`. Keep existing
`compare-selected-files` requests compatible and restricted to two files.

Decode and route operations explicitly in `FinderComparisonRequest` and
`ClipDiffApplicationDelegate`. Validate operation, arity and file URLs in the app
as well as the extension. Reject missing/extra file arguments, non-file URLs and
unknown operations; malformed custom URLs must not fall through as file inputs.
Preserve URL escaping and file order for spaces, Unicode, `&`, `#`, `+` and `%`.

Keep `addsToRecentItems = false`. Do not put captured contents in the handoff or
add preferences, files, notifications or logs containing captures or source paths.
Source paths remain limited to pending in-memory work and the two retained history
entries; generated diff documents keep resolved labels, not full source paths.
The existing explicitly selected external-viewer exception continues to apply.

This task reuses the current transport; it does not investigate or redesign its
operating-system retention behavior. Preserve the merged incoming pasteboard
privacy screening and the existing Copy diff output policy.

## Acceptance and verification

Add focused tests exercising the production request and state-transition logic.
Use injected reads/fakes or a small Foundation-only coordinator to control delayed
completions; do not rely on timing sleeps or tests of an unused parallel model.

Cover:

1. One-file request round trips, malformed request rejection, and unchanged
   two-file request round trips and ordering.
2. Capture plus selected file produces the correct Previous/Current pair,
   preserves the old Current metadata, drops the older entry and handles identical
   text. Include a captured file whose original contents have since changed.
3. No capture causes no content read or history mutation; paused comparison works
   and remains paused. The action makes no pasteboard payload reads or writes.
4. Controlled delayed completions after clear, a new capture (including identical
   text), a newer Finder request, Copy diff and a monitoring transition cannot
   commit. Cover an ignored pasteboard change while monitoring, a change before
   the timer observes it, and allowed clipboard changes while paused.
5. Existing reader fallbacks and labels are used, and a clipboard clear after a
   successful direct comparison leaves that pair intact.

Run `swift test` where supported. On macOS, build both the app and Finder extension
using the existing build setup and perform a native smoke check: one-file text
and file captures, no-capture/cold-start message, paused operation, unsupported
selection counts, unchanged clipboard, same-basename labels, two-file cold start,
and the external-viewer warning/fallback. The repository's local smoke workflow
starts with `scripts/create-local-release.sh`.

Report actual commands/results and any checks the cloud environment cannot run.
A portable test pass does not establish that the Finder extension builds or works.

Add this specification under `docs/finder-single-file-comparison.md`. Update the
Finder sections and manual checks in `README.md` and `AGENTS.md`; add a dated
implementation-status note to the feature-gap report while preserving its original
comparison baseline. Keep changes limited to this feature, its tests and docs.

