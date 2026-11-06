#!/bin/bash
# Fills dist from an archive of the xcframeworks, after checking its SHA-256.
# Usage: fetch-dist.sh <local file or URL> <sha256> [dist folder]
set -euo pipefail
SOURCE=${1:?local file or URL}
EXPECTED=${2:?sha256}
DEST=${3:-${FINESSE_DEPS_WORK:-$HOME/Developer/FinesseDeps}/dist}
FRAMEWORKS=14

mkdir -p "$(dirname "$DEST")"
TEMP=$(mktemp -d "$DEST.fetch.XXXXXX")
trap 'rm -rf "$TEMP"' EXIT

case "$SOURCE" in
  http://*|https://*) curl -fsSL --retry 5 --retry-all-errors --retry-delay 30 -o "$TEMP/archive" "$SOURCE" ;;
  *) cp "$SOURCE" "$TEMP/archive" ;;
esac

ACTUAL=$(shasum -a 256 "$TEMP/archive" | cut -d' ' -f1)
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "Refusing: SHA-256 is $ACTUAL, expected $EXPECTED" >&2
  exit 1
fi

mkdir "$TEMP/dist"
tar -xf "$TEMP/archive" -C "$TEMP/dist"
COUNT=$(find "$TEMP/dist" -maxdepth 1 -name '*.xcframework' | wc -l | tr -d ' ')
if [ "$COUNT" != "$FRAMEWORKS" ]; then
  echo "Refusing: the archive has $COUNT xcframeworks, expected $FRAMEWORKS" >&2
  exit 1
fi

rm -rf "$DEST"
mv "$TEMP/dist" "$DEST"
echo "$DEST filled with $COUNT xcframeworks"
