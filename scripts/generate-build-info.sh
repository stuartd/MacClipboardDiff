#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# Run on every build so switching branches or committing refreshes About.
# Explicit build settings also support builds from a source archive. Only a
# tagged release build supplies CLIPDIFF_RELEASE_TAG; local Release builds do not.
COMMIT="${GIT_COMMIT:-$(git_commit)}"
OUTPUT_PLIST="$DERIVED_FILE_DIR/ClipDiff-Info.plist"
TEMP_PLIST="$(mktemp "$DERIVED_FILE_DIR/ClipDiff-Info.XXXXXX")"
trap 'rm -f "$TEMP_PLIST"' EXIT

cp "$REPO_ROOT/ClipDiff-Info.plist" "$TEMP_PLIST"
plutil -replace ClipDiffGitCommit -string "$COMMIT" "$TEMP_PLIST"
plutil -replace ClipDiffReleaseTag -string "${CLIPDIFF_RELEASE_TAG:-}" "$TEMP_PLIST"

# Preserve the timestamp when unchanged to avoid unnecessary plist processing.
if ! cmp -s "$TEMP_PLIST" "$OUTPUT_PLIST"; then
    mv "$TEMP_PLIST" "$OUTPUT_PLIST"
fi
