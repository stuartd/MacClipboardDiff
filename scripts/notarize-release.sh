#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

if [[ $# != 2 ]]; then
    echo "Usage: SIGNING_IDENTITY='Developer ID Application: …' NOTARY_PROFILE='…' $0 APP_PATH OUTPUT_DIR" >&2
    exit 2
fi
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application certificate name or SHA-1.}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool Keychain profile.}"

APP_PATH="$1"
OUTPUT_DIR="$2"
EXTENSION_PATH="$APP_PATH/Contents/PlugIns/ClipDiffFinderSync.appex"
if [[ ! -d "$APP_PATH" || ! -d "$EXTENSION_PATH" ]]; then
    echo "Expected ClipDiff.app with its embedded Finder extension: $APP_PATH" >&2
    exit 1
fi

NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
SIGNING_ARGS=(--options runtime --timestamp)
IDENTITY_ARGS=(-v -p codesigning)
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
    NOTARY_ARGS+=(--keychain "$SIGNING_KEYCHAIN")
    SIGNING_ARGS+=(--keychain "$SIGNING_KEYCHAIN")
    IDENTITY_ARGS+=("$SIGNING_KEYCHAIN")
fi

# Reject development/ad hoc identities before signing anything. Resolve a name
# or SHA-1 to exactly one Developer ID Application identity in this keychain.
IDENTITIES="$(security find-identity "${IDENTITY_ARGS[@]}")"
IDENTITY_HASH="$(printf '%s\n' "$IDENTITIES" | awk -v identity="$SIGNING_IDENTITY" '
    /"Developer ID Application:/ {
        hash = $2
        name = $0
        sub(/^[^"]*"/, "", name)
        sub(/"[[:space:]]*$/, "", name)
        if (hash == identity || name == identity) { print hash; count++ }
    }
    END { if (count != 1) exit 1 }
')" || {
    echo "Expected exactly one valid Developer ID Application identity matching SIGNING_IDENTITY." >&2
    exit 1
}

# Check credentials before changing the app. Credentials stay in the Keychain.
xcrun notarytool history "${NOTARY_ARGS[@]}" --output-format json >/dev/null
for ARCH in arm64 x86_64; do
    lipo "$APP_PATH/Contents/MacOS/ClipDiff" -verify_arch "$ARCH"
    lipo "$EXTENSION_PATH/Contents/MacOS/ClipDiffFinderSync" -verify_arch "$ARCH"
done

mkdir -p "$OUTPUT_DIR/notarization"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
WORK_DIR="$(mktemp -d "$OUTPUT_DIR/.notarization.XXXXXX")"
cleanup() {
    local result=$?
    if [[ $result == 0 ]]; then
        rm -rf "$WORK_DIR"
    else
        echo "Notarization stopped. Build and diagnostics retained at: $WORK_DIR" >&2
    fi
}
trap cleanup EXIT

# Sign nested code first, with its own entitlements; never use --deep to sign.
# The host app is intentionally unsandboxed and needs no entitlements.
codesign --force --sign "$IDENTITY_HASH" "${SIGNING_ARGS[@]}" \
    --entitlements "$REPO_ROOT/ClipDiffFinderSync/ClipDiffFinderSync.entitlements" \
    "$EXTENSION_PATH"
codesign --force --sign "$IDENTITY_HASH" "${SIGNING_ARGS[@]}" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$WORK_DIR/notarization.zip"
SUBMISSION="$OUTPUT_DIR/notarization/submission.json"
NOTARY_LOG="$OUTPUT_DIR/notarization/log.json"
SUBMIT_RESULT=0
xcrun notarytool submit "$WORK_DIR/notarization.zip" \
    "${NOTARY_ARGS[@]}" \
    --wait --timeout 30m --output-format json > "$SUBMISSION" || SUBMIT_RESULT=$?
cat "$SUBMISSION"

# A rejected submission may return a nonzero exit status. Retrieve its log too,
# and preserve the submission ID if Apple's processing outlasts our timeout.
SUBMISSION_ID="$(plutil -extract id raw -o - "$SUBMISSION" 2>/dev/null || true)"
if [[ -n "$SUBMISSION_ID" ]]; then
    xcrun notarytool log "$SUBMISSION_ID" \
        "${NOTARY_ARGS[@]}" \
        "$NOTARY_LOG" || echo "Notarization log is not available yet." >&2
fi
STATUS="$(plutil -extract status raw -o - "$SUBMISSION" 2>/dev/null || true)"
if [[ $SUBMIT_RESULT != 0 || "$STATUS" != Accepted ]]; then
    echo "Notarization did not complete with Accepted status; no release ZIP was produced." >&2
    exit 1
fi

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

# Stapling changes the bundle. Verify the exact archive that users download.
ZIP_NAME="ClipDiff-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$WORK_DIR/$ZIP_NAME"
ditto -x -k "$WORK_DIR/$ZIP_NAME" "$WORK_DIR/check"
CHECKED_APP="$WORK_DIR/check/$APP_BUNDLE_NAME"
codesign --verify --deep --strict --verbose=2 "$CHECKED_APP"
xcrun stapler validate "$CHECKED_APP"
spctl --assess --type execute --verbose=4 "$CHECKED_APP"

mv "$WORK_DIR/$ZIP_NAME" "$OUTPUT_DIR/$ZIP_NAME"
(cd "$OUTPUT_DIR" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")
cat "$OUTPUT_DIR/$ZIP_NAME.sha256"
echo "Verified notarized release: $OUTPUT_DIR/$ZIP_NAME"
