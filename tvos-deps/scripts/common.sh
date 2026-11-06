# Sourced by every step. Usage: source common.sh <slice>, where slice is tvos or tvossim.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEPS_ROOT=$(cd "$HERE/.." && pwd)
source "$DEPS_ROOT/versions.sh"
WORK=${FINESSE_DEPS_WORK:-$HOME/Developer/FinesseDeps}
SRC=$WORK/src
# At most half the Mac's cores, as well as low priority, because it also runs production work.
export JOBS=${JOBS:-4}
mkdir -p "$WORK/tools/bin"
ln -sf "$HERE/capped-xcodebuild.sh" "$WORK/tools/bin/xcodebuild"
export PATH="$WORK/tools/bin:$WORK/tools/venv/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SLICE=${1:-tvos}
case "$SLICE" in
  tvos)    SDK_NAME=appletvos;        TRIPLE=arm64-apple-tvos$TVOS_DEPLOYMENT_TARGET ;;
  tvossim) SDK_NAME=appletvsimulator; TRIPLE=arm64-apple-tvos$TVOS_DEPLOYMENT_TARGET-simulator ;;
  *) echo "unknown slice $SLICE" >&2; exit 2 ;;
esac
SDK=$(xcrun --sdk "$SDK_NAME" --show-sdk-path)
CC_BIN=$(xcrun --sdk "$SDK_NAME" -f clang)
CXX_BIN=$(xcrun --sdk "$SDK_NAME" -f clang++)
BUILD=$WORK/build/$SLICE
PREFIX=$BUILD/prefix
mkdir -p "$BUILD" "$PREFIX/lib/pkgconfig" "$PREFIX/include"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_PATH || true
BASE_FLAGS="-target $TRIPLE -isysroot $SDK -O2 -fPIC"
LINK_FLAGS="-target $TRIPLE -isysroot $SDK -Wl,-headerpad_max_install_names -Wl,-dead_strip"

quoted_list() { printf "'%s'," "$@" | sed 's/,$//'; }

write_cross_file() {
  local flags links
  flags=$(quoted_list $BASE_FLAGS -I"$PREFIX/include")
  links=$(quoted_list $LINK_FLAGS -L"$PREFIX/lib")
  cat > "$BUILD/cross.ini" <<C
[binaries]
c = '$CC_BIN'
cpp = '$CXX_BIN'
objc = '$CC_BIN'
objcpp = '$CXX_BIN'
ar = '$(xcrun --sdk "$SDK_NAME" -f ar)'
strip = '$(xcrun --sdk "$SDK_NAME" -f strip)'
pkg-config = '/opt/homebrew/bin/pkg-config'

[built-in options]
c_args = [$flags]
cpp_args = [$flags]
objc_args = [$flags]
objcpp_args = [$flags]
c_link_args = [$links]
cpp_link_args = [$links]
objc_link_args = [$links]
objcpp_link_args = [$links]

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'darwin'
subsystem = 'tvos'
kernel = 'xnu'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
C
}

# Fresh copy of a source tree for this slice, so slices can't contaminate each other.
fresh_tree() {
  local name=$1
  rm -rf "$BUILD/$name"
  mkdir -p "$BUILD/$name"
  cp -R "$SRC/$name/." "$BUILD/$name/"
  cd "$BUILD/$name"
}

meson_build() {
  local library=$1; shift
  write_cross_file
  nice -n 15 meson setup _b --cross-file "$BUILD/cross.ini" --prefix "$PREFIX" --libdir lib \
    --buildtype release --default-library "$library" -Dstrip=false --wrap-mode nodownload "$@"
  nice -n 15 ninja -C _b -j "$JOBS"
  ninja -C _b install
}
