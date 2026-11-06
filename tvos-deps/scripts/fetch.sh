#!/bin/bash
# Downloads every source and checks it. --record writes checksums.sha256 instead of checking.
source "$(dirname "$0")/common.sh" tvos
RECORD=${1:-}
SUMS=$DEPS_ROOT/checksums.sha256
mkdir -p "$SRC/tarballs"
if [ "$RECORD" = --record ]; then : > "$SUMS"; fi

tarball() {
  local name=$1 url=$2 file
  file=$(basename "$url")
  if [ ! -f "$SRC/tarballs/$file" ]; then
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 30 --max-time 300 -o "$SRC/tarballs/$file.part" "$url"
    mv "$SRC/tarballs/$file.part" "$SRC/tarballs/$file"
  fi
  if [ "$RECORD" = --record ]; then
    (cd "$SRC/tarballs" && shasum -a 256 "$file") >> "$SUMS"
  else
    (cd "$SRC/tarballs" && grep " $file\$" "$SUMS" | shasum -a 256 -c -)
  fi
  rm -rf "${SRC:?}/$name"
  mkdir -p "$SRC/$name"
  tar -xf "$SRC/tarballs/$file" -C "$SRC/$name" --strip-components=1
}

gitsource() {
  local name=$1 repo=$2 tag=$3 commit=$4
  if [ ! -d "$SRC/$name/.git" ]; then
    rm -rf "${SRC:?}/$name"
    git clone -q --branch "$tag" "$repo" "$SRC/$name"
  fi
  git -C "$SRC/$name" checkout -q "$commit"
  [ "$(git -C "$SRC/$name" rev-parse HEAD)" = "$commit" ] || { echo "$name is not at $commit" >&2; exit 1; }
  git -C "$SRC/$name" submodule --quiet update --init --recursive
}

tarball freetype "$FREETYPE_URL"
tarball fribidi "$FRIBIDI_URL"
tarball harfbuzz "$HARFBUZZ_URL"
tarball libass "$LIBASS_URL"
tarball dav1d "$DAV1D_URL"
tarball ffmpeg "$FFMPEG_URL"
tarball openssl "$OPENSSL_URL"
tarball uchardet "$UCHARDET_URL"
gitsource vulkan-headers "$VULKAN_HEADERS_REPO" "$VULKAN_HEADERS_TAG" "$VULKAN_HEADERS_COMMIT"
gitsource glslang "$GLSLANG_REPO" "$GLSLANG_TAG" "$GLSLANG_COMMIT"
gitsource libplacebo "$LIBPLACEBO_REPO" "$LIBPLACEBO_TAG" "$LIBPLACEBO_COMMIT"
gitsource mpv "$MPV_REPO" "$MPV_TAG" "$MPV_COMMIT"
gitsource moltenvk "$MOLTENVK_REPO" "$MOLTENVK_TAG" "$MOLTENVK_COMMIT"
echo fetched
