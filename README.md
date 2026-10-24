# ClipDiff

ClipDiff is a tiny macOS menu bar utility for comparing the last two copied text values or text files.

## Run It

```sh
scripts/create-local-release.sh
```

The app is copied to `releases/ClipDiff.app` and opened.

## GitHub Release Build

Push a tag starting with `v` to build and publish a GitHub Release:

```sh
git tag v0.9.0
git push origin v0.9.0
```

The workflow runs the core tests and builds the app and Finder extension in
Release mode for Apple Silicon and Intel. Tagged builds sign both bundles with
Developer ID, submit the app to Apple for notarization, staple the accepted
ticket, and verify the signature, ticket, and Gatekeeper acceptance after
extracting the final ZIP. Only then does it publish a GitHub Release with
generated release notes, `ClipDiff-macOS.zip`, and a SHA-256 checksum. Extract
the ZIP to get `ClipDiff.app`. Tags containing a hyphen, such as `v0.9.0-rc.1`,
create prereleases. Rerunning a successful tag build replaces the assets on its
existing release. Missing credentials or failed notarization stop publication;
tagged builds never fall back to ad hoc signing.

For a build from a branch, choose **Actions → Build Release → Run workflow**.
Download the **ClipDiff-macOS** artifact from that run. Branch builds use ad hoc
signing, require no Apple credentials, and do not publish a GitHub Release.
They are not notarized, so macOS Gatekeeper may require approval before opening
them. Manually rerunning the workflow on a `v*` tag uses the notarized release
path.

About shows the tag for tagged releases (for example, **Version v0.9.0**) and the short commit
for other builds (for example, **Commit abc1234**), including local Release builds.
The source commit is embedded in every build; the bundle version and build number
still come from the Xcode project. Publishing uses GitHub's built-in token.

### One-time Apple credentials setup

In [repository Actions secrets](https://github.com/stuartd/MacClipboardDiff/settings/secrets/actions),
add the following repository secrets before pushing a release tag:

| Secret | Value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded `.p12` export of one **Developer ID Application** certificate and its private key. |
| `P12_PASSWORD` | Password chosen when exporting that `.p12`. |
| `APPLE_ID` | Apple Account email used for notarization. |
| `APPLE_TEAM_ID` | Apple Developer team ID, currently `ZQ5KWSZ72K`. |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password generated for notarization at [account.apple.com](https://account.apple.com/). |

An existing Developer ID Application certificate and notarization account used
for another app, such as MacDiff, can be reused. In Keychain Access, select the
certificate under **My Certificates** and export it with its private key as a
password-protected `.p12`. An Apple Development certificate is not suitable.
For example, upload the certificate directly to GitHub without printing it or
copying it through ClipDiff's monitored clipboard:

```sh
base64 -i /path/to/DeveloperID.p12 | gh secret set BUILD_CERTIFICATE_BASE64 --repo stuartd/MacClipboardDiff
gh secret set P12_PASSWORD --repo stuartd/MacClipboardDiff
gh secret set APPLE_ID --repo stuartd/MacClipboardDiff
gh secret set APPLE_TEAM_ID --repo stuartd/MacClipboardDiff
gh secret set APPLE_APP_SPECIFIC_PASSWORD --repo stuartd/MacClipboardDiff
```

The commands without piped input prompt for the value. A local `notarytool`
Keychain profile is not automatically available on GitHub runners. The workflow
imports the certificate into a temporary Keychain, validates the notarization
credentials before building, and deletes the Keychain at the end of the job.
Apple's submission result and available notarization log are retained as a
separate **ClipDiff-notarization** workflow artifact, including on failure.
Never commit signing certificates, private keys, or passwords to this repository.

### Notarize a local build

With the Developer ID certificate installed and a `notarytool` Keychain profile
already configured, the same signing and packaging script can notarize an
existing universal Release build:

```sh
SIGNING_IDENTITY="Developer ID Application: Stuart Dunkeld (ZQ5KWSZ72K)" \
NOTARY_PROFILE="ClipDiff-Notary" \
  scripts/notarize-release.sh /path/to/ClipDiff.app releases/notarized
```

The input app must contain both Intel and Apple Silicon executables, including
the Finder extension. This modifies its signatures and adds the notarization
ticket. The verified ZIP and checksum go in the output directory, alongside
notarization diagnostics. This command does not publish a GitHub Release.

## Running ClipDiff

ClipDiff runs one instance per user. Launching it again activates the running
instance and exits the duplicate without requesting a diff. To switch to a newly
built version, quit the running app first; quitting discards its captured text.

On its first ordinary launch, ClipDiff asks whether to **Start at Login**. Either
answer is remembered; the menu toggle lets you change it later. If first launched
for a Finder comparison, the question waits until the next ordinary launch.
Login launches stay quiet, showing only the menu bar icon. The toggle follows
the actual macOS setting, including changes made in System Settings. If macOS
requires approval, the menu says so and offers **Open Login Items…**.

Turning off **Start at Login** affects future sign-ins. ClipDiff captures clipboard
changes whenever it is running. **Quit ClipDiff** stops capture and discards the
captured text.

Enable startup from the Release app at a stable location, rather than a temporary
Xcode build, so macOS can find that copy at login.

## Workflow

1. Copy the older text or file.
2. Copy the newer text or file.
3. Press `Option-Command-C`, or choose **Show Diff** from the menu bar item. Choose **Change Keyboard Shortcut…** in that menu to record a different global shortcut.
4. View the diff in the selected viewer. The built-in native window remains the default.

You can also copy exactly two files together in Finder. ClipDiff immediately treats the first file as **Previous** and the second as **Current**.

Custom shortcuts must include Option or Control; Command and Shift are optional. The shortcut recorder checks enabled macOS system shortcuts and ClipDiff’s own menu commands. The same checks run at startup before registering the saved shortcut. It explains known conflicts and registration failures, and keeps the current shortcut active if a replacement fails. While the recorder has focus, pressing the current shortcut records it instead of opening a diff. **Use Default** selects `Option-Command-C`; **Save** applies it, and **Cancel** leaves the saved shortcut unchanged. These checks cannot identify every shortcut used inside other apps.

## Finder Context Menu

The app includes a Finder Sync extension. Choose **Finder Menu Settings…** in the ClipDiff menu to open macOS System Settings, then enable or disable **ClipDiff Finder Integration** there. With exactly one regular file selected, Finder shows **Compare with current ClipDiff capture**. It reads the selected file only after invocation, moves the current in-memory capture to **Previous**, makes the selected file **Current**, and opens the configured viewer without changing the clipboard. If there is no capture (including after a cold start), ClipDiff activates and explains that text or a file must first be copied while the app is running.

The one-file command is hidden when the selection has the same standardized path as the current file capture. Files with matching names in different folders remain comparable. The extension receives only an in-memory, session-salted path fingerprint, and ClipDiff rechecks the path before accepting the comparison.

Finder’s **Copy as Pathname** also works for a single absolute path to a readable, non-empty text file. Copy the pathname, then choose **Compare with current ClipDiff capture** on another text file. ClipDiff finishes any pending pathname capture before starting the comparison, and a new copy prevents an older capture from hiding that command.

With exactly two regular files selected, Finder shows **Compare two selected files with ClipDiff**. Choosing it opens ClipDiff if necessary, reads and classifies the pair, replaces the in-memory comparison pair, and immediately shows the diff; the first Finder selection is **Previous** and the second is **Current**. A comparison containing a binary file leaves the current captures untouched. Other unusable files use the documented filename-and-reason fallback. Zero, more than two, or any folder/non-regular selection shows neither command.

## Copied Files

Finder file URLs take precedence over incidental path text on the pasteboard. A single copied file becomes one capture; exactly two copied files atomically replace the comparison pair; copies containing more than two files are ignored.

Binary files, including ZIP archives, are ignored without changing the current captures. If either file in a copied pair is binary, the entire copy is ignored.

For a usable text file, ClipDiff reads and retains the complete decoded contents in memory. It supports UTF-8, BOM-marked UTF-16 and UTF-32, common BOM-less UTF-16, and Windows-1252. Files larger than 16 MiB are not read.

Other unusable files contribute their filename followed by a reason:

- `(directory)`
- `(empty file)`
- `(file not found)`
- `(file unreadable)`
- `(file too large)`

The source filename is shown in side-by-side headings and unified diff headers. When both files have the same basename, ClipDiff adds only enough parent directories to distinguish them, such as `branch-a/Sources/settings.json` and `branch-b/Sources/settings.json`.

The full standardized file path is retained only with the corresponding in-memory history entry. A generated diff keeps its resolved display label but drops the full path. File contents and paths are never logged, uploaded, indexed, or persisted.

## Design

- The app monitors `NSPasteboard.changeCount` and captures only future changes.
- A per-user file lock prevents duplicate clipboard monitors and hotkeys. Its file
  in `~/Library/Application Support/ClipDiff/instance.lock` contains only a process
  ID; macOS releases the lock when the owning process exits, including after a crash.
- The optional Finder extension uses selection metadata and the current capture's path fingerprint to choose the one-file or two-file command. File contents are read only after that command is chosen; the app rechecks selection requests and asynchronous capture identity before committing.
- Plain text and one or two copied file URLs are supported.
- Separate copy events are captured even when their text is identical.
- Unsupported non-text changes are ignored without clearing history.
- A copied value immediately followed by an explicit clipboard clear within 60 seconds is removed as a best-effort privacy measure.
- Captured content is kept in memory only and lost when the app exits.
- Slow file reads are superseded if a newer pasteboard change arrives.
- Clipboard items marked `org.nspasteboard.ConcealedType` or
  `org.nspasteboard.TransientType` are ignored before ClipDiff reads
  either their text or file URLs. These advisory markers are commonly used by
  password managers and other privacy-conscious clipboard producers.
- The built-in diff is native SwiftUI and never writes captured text to disk.

## External Diff Viewers

The menu's **Diff viewer** submenu lists supported applications found on the Mac, provides **Choose Application…** for another app or executable, and lets you return to the built-in viewer. The selection is remembered.

ClipDiff recognizes these viewer profiles:

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

ClipDiff supplies those labels to Beyond Compare, Araxis Merge, KDiff3, Meld, and SourceGear DiffMerge. For example, two files named `README.md` can appear as **Previous clipboard — old/README.md** and **Current clipboard — new/README.md**. These viewers still read temporary copies of the captured text; the labels describe the original sources. VS Code and Cursor's command-line diff integration does not accept custom side titles, so they may display the temporary paths. Other viewer profiles preserve the source basenames where available and let the viewer choose how to display them.

The local build is not App Sandbox-restricted because it must start the explicitly selected external executable. The app remains dependency-free and does not add network access or broaden its clipboard and copied-file workflow.

## Diff View

The default view is side-by-side:

- previous text on the left
- current text on the right
- changed and removed lines tinted red
- changed and added lines tinted green

There is also a unified view for copying or scanning a compact diff. Diff rows are rendered lazily so larger text files do not eagerly construct every visible row.

## Privacy Limitations

The recent-clear behavior is only a heuristic. An unmarked secret is otherwise indistinguishable from ordinary text, and Swift strings cannot be guaranteed to be securely zeroed. Operating-system paging, process dumps, other clipboard monitors, and macOS clipboard behavior are outside ClipDiff's control.

Concealed and transient pasteboard markers are advisory and depend on the source
application providing them. ClipDiff does not guess whether unmarked text
is sensitive from its contents, length, or source application.

The built-in viewer keeps the memory-only privacy model. Selecting an external viewer creates an explicit exception because another application cannot compare the captured strings directly. Before the first external comparison, ClipDiff warns that clipboard text may contain secrets and asks for confirmation. Cancelling opens the built-in viewer and creates no files.

After confirmation, each comparison writes two read-only UTF-8 plaintext files to a unique directory below the system temporary directory. ClipDiff attempts to delete that directory after the launched comparison process exits, when ClipDiff exits, and on its next launch. Cleanup is best effort: a crash, power loss, open file handle, or external application may leave or retain a copy. Do not select an external viewer when that disk exposure is unacceptable.

Only the selected executable path, the one-time warning acknowledgement, the chosen global shortcut, and whether the Start at Login question was handled are stored in app preferences. macOS manages the login-item registration. Clipboard text, previews, diffs, and source paths are never stored there.

## Tests

The SwiftPM XCTest suite covers clipboard history, privacy-marker payload
exclusion, recent clears, copied-file decoding and fallback behavior, filename
disambiguation, version formatting, and line-based diff behavior:

```sh
swift test
```

Login-item tests use fake services and presenters to cover the one-time prompt,
menu changes, external setting changes, approval, failures, and quiet automatic
or Finder launches. After building, check the first-launch question and menu
toggle, change the setting in System Settings and reopen the menu, then sign out
and back in to verify a quiet launch. Declining the question or turning startup
off should not cause another question on later launches.

For Finder changes, also build the app and extension on macOS with `scripts/create-local-release.sh`, then smoke-test one-file captured-text/captured-file comparisons, the visible no-capture message, capture continuing after a comparison, unchanged clipboard, same-basename labels, unsupported selections, two-file cold start, and external-viewer warning/fallback.

For external-viewer labels, compare two files with the same basename in different folders in Beyond Compare or Meld. Confirm the panes show the shortest distinguishing source labels, including names containing spaces or Unicode. Also check plain-text captures still show **Previous clipboard** and **Current clipboard**.
