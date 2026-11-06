#!/bin/bash
# mpv as an LGPL library: -Dgpl=false, with only the components the player uses.
source "$(dirname "$0")/common.sh" "$1"
fresh_tree mpv
for patch in "$DEPS_ROOT"/patches/mpv/*.patch; do
  git apply --whitespace=nowarn "$patch"
done
meson_build shared -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false -Dfuzzers=false \
  --auto-features=disabled \
  -Dpthread-debug=disabled -Diconv=enabled -Dlibavdevice=disabled \
  -Dvulkan=enabled -Dgl=disabled -Dvideotoolbox-pl=enabled -Dvideotoolbox-gl=disabled \
  -Daudiounit=enabled -Davfoundation=enabled -Dcoreaudio=disabled -Dcocoa=disabled -Dswift-build=disabled \
  -Dlua=disabled -Djavascript=disabled -Dmanpage-build=disabled -Dhtml-build=disabled -Dpdf-build=disabled
# Meson's report of what was enabled, for the record and for the licence check below.
grep -E '^#define HAVE_(GPL|VULKAN|MOLTENVK|VIDEOTOOLBOX_PL|AVFOUNDATION|AUDIOUNIT|BSD_FSTATFS|COCOA) ' _b/config.h
if grep -qE '^#define HAVE_GPL 1' _b/config.h; then
  echo "Refusing: mpv was configured with GPL" >&2
  exit 1
fi
if grep -qE '^#define HAVE_BSD_FSTATFS 1' _b/config.h; then
  echo "Refusing: fstatfs is still in the build" >&2
  exit 1
fi
