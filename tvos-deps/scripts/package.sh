#!/bin/bash
# Wraps each slice's dylibs as frameworks and makes the xcframeworks in $WORK/dist.
# Output goes to dist only. Binaries are never committed to the repo.
source "$(dirname "$0")/common.sh" tvos
DIST=$WORK/dist
rm -rf "${DIST:?}"
mkdir -p "$DIST"
python3 "$HERE/make_frameworks.py" "$WORK" "$DIST" "$DEPS_ROOT" "$TVOS_DEPLOYMENT_TARGET"
# Each slice carries its dSYM, which Xcode copies into an app's archive for symbolication.
for name in $(cat "$DIST/frameworks.txt"); do
  xcodebuild -create-xcframework \
    -framework "$DIST/slices/tvos/$name.framework" -debug-symbols "$DIST/slices/tvos/$name.framework.dSYM" \
    -framework "$DIST/slices/tvossim/$name.framework" -debug-symbols "$DIST/slices/tvossim/$name.framework.dSYM" \
    -output "$DIST/$name.xcframework" >/dev/null
done
rm -rf "${DIST:?}/slices.keep"
mv "$DIST/slices" "$DIST/slices.keep"
du -sh "$DIST"/*.xcframework
