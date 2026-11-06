#!/bin/bash
# uchardet lets mpv guess the character set of old subtitles that aren't UTF-8.
source "$(dirname "$0")/common.sh" "$1"
fresh_tree uchardet
case "$SLICE" in
  tvos) SYSROOT=appletvos ;;
  tvossim) SYSROOT=appletvsimulator ;;
esac
nice -n 15 cmake -S . -B _b -G Ninja \
  -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_OSX_SYSROOT="$SYSROOT" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$TVOS_DEPLOYMENT_TARGET" \
  -DCMAKE_C_COMPILER="$CC_BIN" -DCMAKE_CXX_COMPILER="$CXX_BIN" \
  -DCMAKE_C_FLAGS="$BASE_FLAGS" -DCMAKE_CXX_FLAGS="$BASE_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$LINK_FLAGS" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_INSTALL_NAME_DIR=@rpath \
  -DBUILD_SHARED_LIBS=ON -DBUILD_BINARY=OFF -DBUILD_STATIC=OFF
nice -n 15 cmake --build _b -j "$JOBS"
cmake --install _b
