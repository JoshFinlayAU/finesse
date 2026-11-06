# Exact sources. Tarballs are checked against checksums.sha256. Git sources are checked out by commit.
# Keep this and checksums.sha256 together: a version change means re-recording with fetch.sh --record.
FREETYPE_VERSION=2.15.0
FREETYPE_URL=https://download.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VERSION.tar.xz
FRIBIDI_VERSION=1.0.18
FRIBIDI_URL=https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz
HARFBUZZ_VERSION=15.1.0
HARFBUZZ_URL=https://github.com/harfbuzz/harfbuzz/releases/download/$HARFBUZZ_VERSION/harfbuzz-$HARFBUZZ_VERSION.tar.xz
LIBASS_VERSION=0.17.5
LIBASS_URL=https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.xz
DAV1D_VERSION=1.5.4
DAV1D_URL=https://downloads.videolan.org/pub/videolan/dav1d/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.xz
FFMPEG_VERSION=8.1.3
FFMPEG_URL=https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz

# The LTS line. FFmpeg links it for TLS 1.3, which is why FFmpeg is built with --enable-version3.
OPENSSL_VERSION=3.5.9
OPENSSL_URL=https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz
UCHARDET_VERSION=0.0.8
UCHARDET_URL=https://www.freedesktop.org/software/uchardet/releases/uchardet-$UCHARDET_VERSION.tar.xz

MPV_REPO=https://github.com/mpv-player/mpv.git
MPV_TAG=v0.42.0
MPV_COMMIT=b0841e8c4d156b8403dc1876c4cbd9011eb583f3
LIBPLACEBO_REPO=https://github.com/haasn/libplacebo.git
LIBPLACEBO_TAG=v7.387.0
LIBPLACEBO_COMMIT=275f7dea27924cdd34ab2e6c20e448b6bc4fab65
GLSLANG_REPO=https://github.com/KhronosGroup/glslang.git
GLSLANG_TAG=vulkan-sdk-1.4.363.0
GLSLANG_COMMIT=e1b562a8bed273a02f30b59b66a5d499793cede5
VULKAN_HEADERS_REPO=https://github.com/KhronosGroup/Vulkan-Headers.git
VULKAN_HEADERS_TAG=vulkan-sdk-1.4.363.0
VULKAN_HEADERS_COMMIT=6802bb4733b63ed5efd3adb308a6c885ef180ea1
MOLTENVK_REPO=https://github.com/KhronosGroup/MoltenVK.git
MOLTENVK_TAG=v1.4.2
MOLTENVK_COMMIT=db66022459ffb663aa2b50f6b018bc2e124f5edf

# Tools, installed by bootstrap.sh into a private venv. Nothing goes in Homebrew.
MESON_VERSION=1.9.1
NINJA_VERSION=1.13.0
CMAKE_VERSION=4.1.2

TVOS_DEPLOYMENT_TARGET=26.0
