#!/bin/bash
# glslang compiles libplacebo's shaders to SPIR-V for MoltenVK, and is static inside libplacebo.
# libplacebo reads Dolby Vision metadata from FFmpeg itself, so libdovi and its Rust build aren't needed.
source "$(dirname "$0")/common.sh" "$1"

fresh_tree glslang
case "$SLICE" in
  tvos) SYSROOT=appletvos ;;
  tvossim) SYSROOT=appletvsimulator ;;
esac
nice -n 15 cmake -S . -B _b -G Ninja \
  -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_OSX_SYSROOT="$SYSROOT" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$TVOS_DEPLOYMENT_TARGET" \
  -DCMAKE_C_COMPILER="$CC_BIN" -DCMAKE_CXX_COMPILER="$CXX_BIN" \
  -DCMAKE_C_FLAGS="$BASE_FLAGS" -DCMAKE_CXX_FLAGS="$BASE_FLAGS" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_SHARED_LIBS=OFF -DENABLE_OPT=OFF -DENABLE_GLSLANG_BINARIES=OFF -DENABLE_HLSL=OFF -DGLSLANG_TESTS=OFF
nice -n 15 cmake --build _b -j "$JOBS"
cmake --install _b

fresh_tree libplacebo
for patch in "$DEPS_ROOT"/patches/libplacebo/*.patch; do
  git apply --whitespace=nowarn "$patch"
done
# Meson finds static libraries by searching directories, not through linker flags.
# libplacebo's lookup of the glslang library itself takes no directories, so name them all here.
export LIBRARY_PATH="$PREFIX/lib"
LINK_FLAGS="$LINK_FLAGS -lglslang -lMachineIndependent -lOSDependent -lGenericCodeGen -lSPIRV -lglslang-default-resource-limits"
meson_build shared -Dprefer_static=true -Dvulkan-sdk="$PREFIX" -Dvulkan=enabled -Dvk-proc-addr=enabled -Dglslang=enabled \
  -Dshaderc=disabled -Dopengl=disabled -Dd3d11=disabled -Dlcms=disabled -Ddovi=enabled -Dlibdovi=disabled \
  -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false -Dxxhash=disabled -Dunwind=disabled
