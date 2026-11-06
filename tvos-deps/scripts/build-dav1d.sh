#!/bin/bash
source "$(dirname "$0")/common.sh" "$1"
fresh_tree dav1d
meson_build shared -Denable_tools=false -Denable_tests=false -Denable_docs=false
