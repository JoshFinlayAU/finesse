#!/bin/bash
# xcodebuild uses every core unless told otherwise, and the build Mac has other work on it.
# common.sh puts this first in PATH as `xcodebuild`, so builds it starts itself are capped too.
# Modes such as -create-xcframework and -version don't accept -jobs, and don't compile anything.
case " $* " in
  *" -create-xcframework "* | *" -version "* | *" -showsdks "* | *" -list "* | *" -showBuildSettings "*)
    exec /usr/bin/xcodebuild "$@"
    ;;
esac
exec /usr/bin/nice -n 15 /usr/bin/xcodebuild -jobs "${JOBS:-4}" "$@"
