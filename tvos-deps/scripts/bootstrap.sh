#!/bin/bash
# Installs the build tools into a private venv, with no sudo and no Homebrew changes.
WORK=${FINESSE_DEPS_WORK:-$HOME/Developer/FinesseDeps}
mkdir -p "$WORK/tools"
/opt/homebrew/bin/python3 -m venv "$WORK/tools/venv"
source "$(dirname "$0")/common.sh" tvos
"$WORK/tools/venv/bin/pip" -q install "meson==$MESON_VERSION" "ninja==$NINJA_VERSION" "cmake==$CMAKE_VERSION" packaging
meson --version
ninja --version
cmake --version | head -1
