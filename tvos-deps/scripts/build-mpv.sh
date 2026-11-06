#!/bin/bash
# mpv as an LGPL library: -Dgpl=false, with only the components the player uses.
source "$(dirname "$0")/common.sh" "$1"
fresh_tree mpv
for patch in "$DEPS_ROOT"/patches/mpv/*.patch; do
  git apply --whitespace=nowarn "$patch"
done
MPV_OPTIONS=(-Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false -Dfuzzers=false
  --auto-features=disabled
  -Dpthread-debug=disabled -Diconv=enabled -Dlibavdevice=disabled
  -Dzlib=enabled -Duchardet=enabled -Dvector=enabled
  -Dvulkan=enabled -Dgl=disabled -Dvideotoolbox-pl=enabled -Dvideotoolbox-gl=disabled
  -Daudiounit=enabled -Davfoundation=enabled -Dcoreaudio=disabled -Dcocoa=disabled -Dswift-build=disabled
  -Dlua=disabled -Djavascript=disabled -Dmanpage-build=disabled -Dhtml-build=disabled -Dpdf-build=disabled)
# mpv would otherwise record its whole meson command line and a config folder under the build prefix.
after_meson_setup() {
  sed -i '' -e "s|^#define CONFIGURATION .*|#define CONFIGURATION \"${MPV_OPTIONS[*]}\"|" \
    -e 's|^#define MPV_CONFDIR .*|#define MPV_CONFDIR "/var/empty/mpv"|' _b/config.h
}
meson_build shared "${MPV_OPTIONS[@]}"
# zlib matters: mkvmerge usually compresses PGS tracks with it, and without it mpv's Matroska demuxer silently
# shows no PGS subtitles. Meson's report of what was enabled, for the record and for the licence check below.
grep -E '^#define HAVE_(GPL|VULKAN|MOLTENVK|VIDEOTOOLBOX_PL|AVFOUNDATION|AUDIOUNIT|BSD_FSTATFS|COCOA|ZLIB|UCHARDET) ' _b/config.h
for needed in ZLIB UCHARDET; do
  grep -qE "^#define HAVE_$needed 1" _b/config.h || { echo "Refusing: $needed is off" >&2; exit 1; }
done
if grep -qE '^#define HAVE_GPL 1' _b/config.h; then
  echo "Refusing: mpv was configured with GPL" >&2
  exit 1
fi
if grep -qE '^#define HAVE_BSD_FSTATFS 1' _b/config.h; then
  echo "Refusing: fstatfs is still in the build" >&2
  exit 1
fi
