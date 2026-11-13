#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: $0 <tag> <commit> [remote] (default: origin)" >&2
    exit 2
fi
TAG="$1"
COMMIT="$2"
REMOTE="${3:-origin}"

skip() {
    echo "$1" >&2
    echo "should_build=false"
    exit 0
}

[[ "$TAG" == v[0-9]* ]] || skip "Skipping $TAG: release tags must start with v and a digit."

# Query the remote, not checkout's shallow/local tags. Keep peeled entries so
# annotated tags can be checked against the commit recorded by the workflow.
REMOTE_TAGS="$(git ls-remote --tags --sort=-version:refname "$REMOTE" 'v[0-9]*')"
HIGHEST_REF=""
while IFS=$'\t' read -r object ref; do
    [[ -n "$ref" && "$ref" != *'^{}' ]] || continue
    HIGHEST_REF="$ref"
    break
done <<< "$REMOTE_TAGS"

[[ -n "$HIGHEST_REF" ]] || skip "Skipping $TAG: no release tags exist on $REMOTE."
[[ "refs/tags/$TAG" == "$HIGHEST_REF" ]] \
    || skip "Skipping $TAG: the highest release tag is ${HIGHEST_REF#refs/tags/}."

TAG_OBJECT=""
PEELED_COMMIT=""
while IFS=$'\t' read -r object ref; do
    if [[ "$ref" == "$HIGHEST_REF" ]]; then
        TAG_OBJECT="$object"
    elif [[ "$ref" == "$HIGHEST_REF^{}" ]]; then
        PEELED_COMMIT="$object"
    fi
done <<< "$REMOTE_TAGS"

[[ "$COMMIT" == "${PEELED_COMMIT:-$TAG_OBJECT}" ]] \
    || skip "Skipping $TAG: the remote tag no longer points to this run's commit."

echo "Building highest release tag $TAG at $COMMIT." >&2
echo "should_build=true"
