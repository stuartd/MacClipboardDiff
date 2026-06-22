#!/usr/bin/env bash

if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "scripts/_common.sh must be sourced from bash." >&2
    return 2 2>/dev/null || exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="$REPO_ROOT/clipdiff.xcodeproj"
SCHEME="clipdiff"
APP_BUNDLE_NAME="ClipDiff.app"
XCODE_APP_BUNDLE_NAME="$APP_BUNDLE_NAME"

git_commit() {
    git -C "$REPO_ROOT" rev-parse --short HEAD
}
