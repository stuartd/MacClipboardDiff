# ClipboardDiff for Mac — notes

## Tiny macOS menu bar app, based on the existing Windows/Ditto ClipboardDiff.

> In macOS 26 Tahoe, Mac clipboard history is built into Spotlight, the universal search box. Launch it like this:


> Hit Command-Space (⌘␣) on the keyboard, then Command-4 (⌘4). You can do this in one quick move — keep your finger on the Command key, then hit Space and 4 in sequence. 
> Click the Spotlight icon in the upper right corner of the menu bar, then click the Clipboard icon on the right of the Spotlight bar.

TODO: Get screenshots of that


> The first time you open Spotlight clipboard history, it’ll ask you if you want to turn on the feature. If you say yes, it will store your 
history from that point onward.

### Core workflow:

1. Select text in old document
2. Copy
3. Select text in new document
4. Copy
5. Press global shortcut
6. See diff between previous clipboard text and current clipboard text

The app only cares about the last two meaningful text clipboard values:

```
previousText
currentText
```

### Basic behaviour:

- Run as menu bar app
- Watch `NSPasteboard.general.changeCount`
- When clipboard changes, read text/plain content
- Ignore duplicates
- Store previous + current text
- On shortcut/menu click, write both values to temp files
- Launch configured diff tool

### MVP:

- Clipboard monitor
- Menu bar icon
- Global shortcut, e.g. `⌥⌘D`
- Diff previous vs current copied text (external diff tool support)

Diff tool approach:

Default macOS option:

`opendiff "{old}" "{new}"`

Other possible commands:

```
code --diff "{old}" "{new}"
diffmerge "{old}" "{new}"
```

Known diff tools:

- FileMerge / opendiff
- VS Code
- DiffMerge/Mac
- Kaleidoscope
- Beyond Compare

