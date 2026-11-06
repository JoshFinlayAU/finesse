#!/bin/bash
# FreeType and HarfBuzz are static and end up inside libass. FriBidi is LGPL, so it stays a replaceable library.
source "$(dirname "$0")/common.sh" "$1"

fresh_tree freetype
meson_build static -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled -Dzlib=disabled -Dtests=disabled

fresh_tree fribidi
meson_build shared -Ddocs=false -Dbin=false -Dtests=false

fresh_tree harfbuzz
meson_build static -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dicu=disabled \
  -Dcoretext=disabled -Dtests=disabled -Dintrospection=disabled -Ddocs=disabled -Dutilities=disabled \
  -Dbenchmark=disabled -Dsubset=disabled

fresh_tree libass
meson_build shared -Dfontconfig=disabled -Dcoretext=enabled -Dlibunibreak=disabled -Drequire-system-font-provider=false -Dtest=disabled
