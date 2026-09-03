#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

CONFIGURATION="${CONFIGURATION:-Release}"
OUTPUT_DIR="${1:-$REPO_ROOT/releases}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
DERIVED_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clipdiff-release-derived-data.XXXXXX")"
BUILD_PRODUCTS_DIR="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION"
BUILT_APP="$BUILD_PRODUCTS_DIR/$XCODE_APP_BUNDLE_NAME"
OUTPUT_APP="$OUTPUT_DIR/$APP_BUNDLE_NAME"
FINDER_EXTENSION="$OUTPUT_APP/Contents/PlugIns/ClipDiffFinderSync.appex"
GIT_COMMIT="$(git_commit)"

cleanup() {
    rm -rf "$DERIVED_DATA_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild clean build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
    GIT_COMMIT="$GIT_COMMIT"

if [[ ! -d "$BUILT_APP" ]]; then
    echo "Built app not found: $BUILT_APP" >&2
    exit 1
fi

echo
echo "Copying app to $OUTPUT_APP..."
rm -rf "$OUTPUT_APP"
ditto "$BUILT_APP" "$OUTPUT_APP"

if [[ -d "$FINDER_EXTENSION" ]]; then
    pluginkit -a "$FINDER_EXTENSION"
fi

echo
echo "Opening $OUTPUT_APP..."
open -n -a "$OUTPUT_APP"

echo
echo "Release artifact:"
echo "App: $OUTPUT_APP"
