#!/bin/bash
# LGPL 2.1 or later: no --enable-gpl, --enable-nonfree or --enable-version3. The result is checked below.
source "$(dirname "$0")/common.sh" "$1"
fresh_tree ffmpeg
nice -n 15 ./configure \
  --prefix="$PREFIX" --install-name-dir='@rpath' \
  --enable-cross-compile --target-os=darwin --arch=aarch64 --sysroot="$SDK" \
  --cc="$CC_BIN" --cxx="$CXX_BIN" --ld="$CC_BIN" \
  --ar="$(xcrun --sdk "$SDK_NAME" -f ar)" --ranlib="$(xcrun --sdk "$SDK_NAME" -f ranlib)" \
  --nm="$(xcrun --sdk "$SDK_NAME" -f nm)" --strip="$(xcrun --sdk "$SDK_NAME" -f strip)" \
  --pkg-config=/opt/homebrew/bin/pkg-config \
  --extra-cflags="$BASE_FLAGS -I$PREFIX/include" --extra-ldflags="$LINK_FLAGS -L$PREFIX/lib" --extra-libs=-liconv \
  --enable-shared --disable-static --enable-pic --disable-debug --disable-doc --disable-programs \
  --disable-autodetect --disable-avdevice --disable-devices --disable-encoders --disable-muxers \
  --enable-network --enable-zlib --enable-bzlib --enable-iconv \
  --enable-videotoolbox --enable-audiotoolbox --enable-securetransport \
  --enable-libdav1d
LICENSE_LINE=$(sed -n 's/^#define FFMPEG_LICENSE "\(.*\)"/\1/p' config.h)
echo "FFmpeg licence reported by configure: $LICENSE_LINE"
[ "$LICENSE_LINE" = "LGPL version 2.1 or later" ] || { echo "Refusing: licence is $LICENSE_LINE" >&2; exit 1; }
# A disabled option is written as !CONFIG_GPL=yes, so the pattern has to start at the line start.
if grep -qE '^CONFIG_(GPL|NONFREE|VERSION3)=yes' ffbuild/config.mak; then
  echo "Refusing: GPL, nonfree or version3 is enabled" >&2
  exit 1
fi
nice -n 15 make -j "$JOBS"
make install
