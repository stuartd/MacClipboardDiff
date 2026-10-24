#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
cd "$REPO_ROOT"

if [[ $# -gt 1 || "${1:-}" == -* ]]; then
    echo "Usage: $0 [remote] (default: origin)" >&2
    exit 2
fi
REMOTE="${1:-origin}"
git remote get-url "$REMOTE" >/dev/null

if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "Commit or stash changes before retagging; the release must use committed source." >&2
    exit 1
fi
TARGET_COMMIT="$(git rev-parse --verify 'HEAD^{commit}')"

# Consult the remote so an unpushed local tag cannot become the latest release.
REMOTE_TAGS="$(git ls-remote --tags --refs --sort=-version:refname "$REMOTE" 'v*')"
if [[ -z "$REMOTE_TAGS" ]]; then
    echo "No v* release tags found on $REMOTE." >&2
    exit 1
fi
IFS=$'\t' read -r OLD_REMOTE_OBJECT TAG_REF <<< "${REMOTE_TAGS%%$'\n'*}"
TAG="${TAG_REF#refs/tags/}"
OLD_LOCAL_OBJECT="$(git rev-parse --verify --quiet "$TAG_REF" || true)"

# Keep the old remote object available for recovery, including annotated tags.
git fetch --no-tags "$REMOTE" "$TAG_REF"
if [[ "$(git rev-parse FETCH_HEAD)" != "$OLD_REMOTE_OBJECT" ]]; then
    echo "$TAG changed on $REMOTE while preparing; run the script again." >&2
    exit 1
fi
OLD_COMMIT="$(git rev-parse --short "$OLD_REMOTE_OBJECT^{commit}")"

REMOTE_DELETED=0
LOCAL_UPDATED=0
rollback() {
    local result=$?
    if [[ $result == 0 ]]; then
        return
    fi
    if [[ $REMOTE_DELETED == 1 ]]; then
        echo "Restoring the previous remote tag after the failed push..." >&2
        if ! git push --no-follow-tags --force-with-lease="$TAG_REF:" \
            "$REMOTE" "$OLD_REMOTE_OBJECT:$TAG_REF"; then
            echo "Could not restore automatically. Check the remote tag before retrying." >&2
            printf 'To retry restoration: git -C %q push --no-follow-tags --force-with-lease=%q %q %q\n' \
                "$REPO_ROOT" "$TAG_REF:" "$REMOTE" "$OLD_REMOTE_OBJECT:$TAG_REF" >&2
        fi
    fi
    if [[ $LOCAL_UPDATED == 1 ]]; then
        if [[ -n "$OLD_LOCAL_OBJECT" ]]; then
            git update-ref "$TAG_REF" "$OLD_LOCAL_OBJECT" "$TARGET_COMMIT" || true
        else
            git update-ref -d "$TAG_REF" "$TARGET_COMMIT" || true
        fi
    fi
    exit "$result"
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Recreating %s on %s: %s -> %s\n' "$TAG" "$REMOTE" \
    "$OLD_COMMIT" \
    "$(git rev-parse --short "$TARGET_COMMIT")"

# Separate deletion and creation also retriggers a release when HEAD is unchanged.
# Explicit leases reject concurrent tag changes instead of overwriting them.
git push --no-follow-tags --force-with-lease="$TAG_REF:$OLD_REMOTE_OBJECT" \
    "$REMOTE" ":$TAG_REF"
REMOTE_DELETED=1
git update-ref "$TAG_REF" "$TARGET_COMMIT" "$OLD_LOCAL_OBJECT"
LOCAL_UPDATED=1
git push --no-follow-tags --force-with-lease="$TAG_REF:" \
    "$REMOTE" "$TARGET_COMMIT:$TAG_REF"
REMOTE_DELETED=0

echo "Pushed $TAG at $(git rev-parse --short "$TARGET_COMMIT"). The release workflow will rebuild it."
