#!/bin/bash
# Builds the throwaway spike app against dist, on its own simulator, away from the Finesse project.
# Usage: spike.sh build, or spike.sh play <name> <seconds> <url> [start] [sid]. Output and screenshots are in $WORK/spike/out.
source "$(dirname "$0")/common.sh" tvossim
SIM="FinesseDeps Apple TV 4K"
SPIKE=$WORK/spike
OUT=$SPIKE/out
mkdir -p "$OUT"

case "$1" in
build)
  rm -rf "$SPIKE/Sources" "$SPIKE/project.yml"
  cp -R "$DEPS_ROOT/spike/." "$SPIKE/"
  cd "$SPIKE"
  xcodegen generate -q
  xcodebuild build -project DepsSpike.xcodeproj -scheme DepsSpike \
    -destination "generic/platform=tvOS Simulator" -derivedDataPath build 2>&1 | grep -E 'error:|warning: .*(ld|dylib)|BUILD (SUCCEEDED|FAILED)|\*\* ' | cut -c1-240
  if ! xcrun simctl list devices available | grep -q "$SIM"; then
    runtime=$(xcrun simctl list runtimes available | sed -n 's/.*\(com\.apple\.CoreSimulator\.SimRuntime\.tvOS-27-2\).*/\1/p' | head -1)
    xcrun simctl create "$SIM" "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K" "$runtime"
  fi
  ;;
play)
  name=$2; seconds=$3; url=$4; start=${5:-0}; sid=${6:-}
  xcrun simctl boot "$SIM" 2>/dev/null || true
  xcrun simctl bootstatus "$SIM" -b >/dev/null
  xcrun simctl install "$SIM" "$SPIKE/build/Build/Products/Debug-appletvsimulator/DepsSpike.app"
  xcrun simctl terminate "$SIM" invalid.placeholder.depsspike 2>/dev/null || true
  # shellcheck disable=SC2086
  rm -f "$OUT/$name.log"
  xcrun simctl launch --terminate-running-process --stdout="$OUT/$name.log" --stderr="$OUT/$name.log" "$SIM" invalid.placeholder.depsspike "$url" "$start" $sid >/dev/null
  sleep "$seconds"
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null 2>&1
  xcrun simctl terminate "$SIM" invalid.placeholder.depsspike 2>/dev/null || true
  grep -E 'SPIKE|\[mpv (cplayer|vo/gpu-next|ffmpeg|ao|file|stream|lavf)[^]]*\].*([Ee]rror|[Ff]ail|tls|TLS|Using|using|VO:|AO:|AID|VID|SID)' "$OUT/$name.log" | tail -30 | cut -c1-220
  ;;
*)
  echo "usage: spike.sh build | play <name> <seconds> <url> [start] [sid]" >&2
  exit 2
  ;;
esac
