#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# Run on every build so switching branches or committing refreshes About.
# An explicit build setting also supports builds from a source archive.
COMMIT="${GIT_COMMIT:-$(git_commit)}"
OUTPUT_PLIST="$DERIVED_FILE_DIR/ClipDiff-Info.plist"
TEMP_PLIST="$(mktemp "$DERIVED_FILE_DIR/ClipDiff-Info.XXXXXX")"
trap 'rm -f "$TEMP_PLIST"' EXIT

cp "$REPO_ROOT/ClipDiff-Info.plist" "$TEMP_PLIST"
/usr/libexec/PlistBuddy -c "Set :ClipDiffGitCommit $COMMIT" "$TEMP_PLIST"

# Preserve the timestamp when unchanged to avoid unnecessary plist processing.
if ! cmp -s "$TEMP_PLIST" "$OUTPUT_PLIST"; then
    mv "$TEMP_PLIST" "$OUTPUT_PLIST"
fi
