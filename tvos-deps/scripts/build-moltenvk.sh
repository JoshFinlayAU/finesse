#!/bin/bash
# MoltenVK builds both slices in one go. Its own script fetches the dependency revisions pinned in
# ExternalRevisions at the MoltenVK commit in versions.sh. The dylib goes in each slice's prefix.
source "$(dirname "$0")/common.sh" tvos
TREE=$WORK/build/moltenvk
rm -rf "$TREE"
mkdir -p "$TREE"
cp -R "$SRC/moltenvk/." "$TREE/"
cd "$TREE"

# Forces the deployment target on every target, including the ones MoltenVK fetches and builds.
cat > "$WORK/build/moltenvk.xcconfig" <<X
TVOS_DEPLOYMENT_TARGET = $TVOS_DEPLOYMENT_TARGET
ARCHS = arm64
GCC_GENERATE_DEBUGGING_SYMBOLS = YES
X
export XCODE_XCCONFIG_FILE=$WORK/build/moltenvk.xcconfig

nice -n 15 ./fetchDependencies --tvos --tvossim
nice -n 15 make tvos tvossim

for pair in "tvos:tvos-arm64" "tvossim:tvos-arm64-simulator"; do
  slice=${pair%%:*}
  variant=${pair##*:}
  prefix=$WORK/build/$slice/prefix
  framework=$TREE/Package/Release/MoltenVK/dynamic/MoltenVK.xcframework/$variant/MoltenVK.framework
  [ -f "$framework/MoltenVK" ] || { echo "No MoltenVK at $framework" >&2; find "$TREE/Package/Release/MoltenVK" -maxdepth 4 >&2; exit 1; }
  mkdir -p "$prefix/lib/pkgconfig" "$prefix/include"
  cp "$framework/MoltenVK" "$prefix/lib/libMoltenVK.dylib"
  # The objects it links from are in Xcode's DerivedData, so make the dSYM now, while they're there.
  rm -rf "$prefix/lib/libMoltenVK.dylib.dSYM"
  dsymutil "$prefix/lib/libMoltenVK.dylib" -o "$prefix/lib/libMoltenVK.dylib.dSYM"
  install_name_tool -id @rpath/libMoltenVK.dylib "$prefix/lib/libMoltenVK.dylib"
  codesign -f -s - "$prefix/lib/libMoltenVK.dylib"
  rm -rf "$prefix/include/vulkan" "$prefix/include/vk_video"
  cp -R "$SRC/vulkan-headers/include/vulkan" "$SRC/vulkan-headers/include/vk_video" "$prefix/include/"
  cat > "$prefix/lib/pkgconfig/vulkan.pc" <<P
prefix=$prefix
Name: Vulkan through MoltenVK
Description: Vulkan headers with MoltenVK as the implementation
Version: ${VULKAN_HEADERS_TAG#vulkan-sdk-}
Libs: -L\${prefix}/lib -lMoltenVK
Cflags: -I\${prefix}/include
P
done
