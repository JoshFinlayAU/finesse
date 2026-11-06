# Finesse tvOS playback dependencies

Scripts that build mpv, FFmpeg and what they need as dynamic frameworks in xcframeworks, for tvOS device and simulator, deployment target 26.0, on Xcode 27.2. These replace MPVKit once the swap test passes.

Binaries are never committed to this repo. See "Storing the frameworks" below. Licences are in `LICENSES.md`.

## What gets built

| Framework | Source | Notes |
|---|---|---|
| Libmpv | mpv 0.42.0 with our three patches | `-Dgpl=false` |
| Libavcodec, Libavfilter, Libavformat, Libavutil, Libswresample, Libswscale | FFmpeg 8.1.3 | `--enable-version3` for OpenSSL, the owner's decision, with no `--enable-gpl` or `--enable-nonfree`. The build stops if configure reports anything but LGPL 3 or later |
| OpenSSL | OpenSSL 3.5.9, the LTS line | libssl and libcrypto as one framework, used only by Libavformat, for TLS 1.3 |
| Libuchardet | uchardet 0.0.8 | Guesses the character set of old subtitles that aren't UTF-8 |
| Libass | libass 0.17.5 | FreeType 2.15.0 and HarfBuzz 15.1.0 are static inside it |
| Libfribidi | FriBidi 1.0.18 | Kept separate because it is LGPL |
| Libdav1d | dav1d 1.5.4 | |
| Libplacebo | libplacebo 7.387.0 | glslang is static inside it |
| MoltenVK | MoltenVK 1.4.2 | Its own dependencies are fetched at the revisions it pins |

Exact sources are in `versions.sh`: tarballs are checked against `checksums.sha256`, and git sources are checked out by commit.

Slices are arm64 only, so the simulator slice doesn't run on an Intel Mac.

Left out compared with MPVKit: GnuTLS, nettle, GMP, libbluray, lcms2, libdovi, libunibreak, shaderc and libavdevice. Consequences:

- GnuTLS, nettle and GMP are unnecessary even with `--enable-version3`. FFmpeg gets TLS from OpenSSL, and nothing else here asks for them. They stay out, and the build refuses them.
- libplacebo reads Dolby Vision metadata from FFmpeg itself rather than through libdovi. Not yet tested on Dolby Vision media.
- Added compared with MPVKit: the `mov_text` and `mlp` decoders.

mpv is configured with `--auto-features=disabled`, so anything it needs has to be named. `-Dzlib=enabled` is not optional: mkvmerge usually compresses PGS tracks with zlib, and without it mpv's Matroska demuxer shows no PGS subtitles and reports no error. The build now refuses to finish with zlib or uchardet off.

## Building

On the Mac, from a copy of this folder. Work goes in `~/Developer/FinesseDeps`, or `FINESSE_DEPS_WORK`. Nothing needs sudo or changes Homebrew.

```sh
scripts/bootstrap.sh
scripts/fetch.sh
scripts/stage.sh "build-fonts.sh tvos" "build-dav1d.sh tvos" "build-openssl.sh tvos" "build-ffmpeg.sh tvos" \
  "build-fonts.sh tvossim" "build-dav1d.sh tvossim" "build-openssl.sh tvossim" "build-ffmpeg.sh tvossim" \
  "build-moltenvk.sh" "build-libplacebo.sh tvos" "build-uchardet.sh tvos" "build-mpv.sh tvos" \
  "build-libplacebo.sh tvossim" "build-uchardet.sh tvossim" "build-mpv.sh tvossim" "package.sh"
python3 scripts/scan.py ~/Developer/FinesseDeps/dist
```

The result is in `~/Developer/FinesseDeps/dist`. Builds run at low priority and use 4 jobs, including `xcodebuild` through `scripts/capped-xcodebuild.sh`, because that Mac also runs production work. Set `JOBS` to change it, and keep it to half the cores or fewer.

`scripts/fetch.sh --record` rewrites the checksums and is only for changing versions.

## Patches

All in `patches/mpv`, against the mpv commit in `versions.sh`. They were written for this project, and MPVKit's were only read to see which areas needed changing.

1. `0001-vulkan-add-context-for-an-app-owned-metal-layer`: upstream mpv's Vulkan context on Apple platforms needs Cocoa. This adds a context that takes the app's `CAMetalLayer` through `--wid`, selected with `gpu-context=moltenvk`.
2. `0002-audio-build-the-avfoundation-output-on-tvos`: the AVFoundation audio output depends on the macOS CoreAudio device layer and Cocoa helpers, which tvOS doesn't have. This guards those parts.
3. `0003-stream-no-fstatfs-on-tvos`: removes `fstatfs`. mpv only uses it to ask whether a local file is on a network mount, which no approved required-reason covers. Without it, `check_stream_network` returns false.

## What the scan proves

`scripts/scan.py` reads the 28 binaries and fails if any of these aren't true:

- no `fstatfs` or other disk space APIs are imported
- OpenSSL only in its own framework and used only by Libavformat, and no GnuTLS, nettle, GMP or mbedTLS anywhere
- each framework has a privacy manifest declaring the required-reason APIs its binary imports
- every Apple symbol imported is listed in the public SDK's `.tbd` stubs
- each binary is the right platform, with minimum OS 26.0 and an `@rpath` install name
- no `--enable-gpl` or `--enable-nonfree` in the binaries, and each FFmpeg library reports LGPL 3 or later

It can't see Objective-C selectors called dynamically, so it doesn't replace App Store validation, which hasn't been run. The file timestamp reason in the manifests (`C617.1`) comes from static analysis of what's imported, not from tracing what the code does at runtime.

## HTTPS

FFmpeg uses OpenSSL 3.5.9, the owner's decision. Tested on the simulator on 2026-11-06:

- A normal HTTPS file played to the end.
- A TLS 1.3 only host connected. It failed with -9836 under Apple's SecureTransport, tried first because it needs no bundled TLS, and which is deprecated and stops at TLS 1.2.

**Known issue to revisit before release: certificates aren't verified.** mpv's `tls-verify` is off by default and `MPVEngine` doesn't set it, by the owner's decision for now. An expired certificate was accepted in testing, so an https server could be impersonated. Turning it on would refuse self-signed home servers, and would also need a CA bundle or a verify callback into Apple's Security framework, because OpenSSL can't read the system's trust store on tvOS.

## Storing the frameworks

A proposal for the owner, not yet in place. Nothing has been published.

- Build on the Mac and make one archive per version, such as `finesse-deps-<versions>-<build>.tar.zst`, holding the xcframeworks.
- Keep the archive in a private store: the generic package registry on `gitlab.athenanetworks.com.au` fits, since the repo is private and that server is ours.
- Commit only its URL and SHA-256 to this folder. A small `fetch-dist.sh` downloads it, checks the hash, and unpacks into a gitignored folder that `project.yml` points at.
- Build on the Mac without fetching when testing a new version.
- Keep the matching source archive and patches alongside each release, because LGPL distribution needs them. See `LICENSES.md`.
