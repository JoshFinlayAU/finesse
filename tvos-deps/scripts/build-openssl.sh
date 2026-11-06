#!/bin/bash
# OpenSSL for FFmpeg's TLS 1.3. libssl and libcrypto become one dylib, so they ship as one framework
# with one manifest. The static archives are removed afterwards, so nothing can link them by accident.
source "$(dirname "$0")/common.sh" "$1"
fresh_tree openssl
# tvOS prohibits fork, and the async code needs APIs that tvOS doesn't allow.
nice -n 15 ./Configure darwin64-arm64 no-shared no-tests no-apps no-docs no-async no-dso no-engine no-legacy no-module \
  no-comp no-ssl3 no-ui-console --prefix=/ --openssldir=/var/empty/ssl --libdir=lib \
  CC="$CC_BIN" CFLAGS="$BASE_FLAGS -DHAVE_FORK=0"
# OpenSSL compiles in its install folders and its whole compiler command, so those are a fixed folder that
# doesn't exist on tvOS and the compiler's name. DESTDIR puts the real install under the build prefix.
perl util/mkbuildinf.pl clang darwin64-arm64 > crypto/buildinf.h
nice -n 15 make -j "$JOBS" build_libs
make install_dev DESTDIR="$PREFIX" >/dev/null

nice -n 15 "$CC_BIN" -dynamiclib -target "$TRIPLE" -isysroot "$SDK" \
  -Wl,-headerpad_max_install_names -install_name @rpath/libOpenSSL.dylib \
  -current_version "$OPENSSL_VERSION" -compatibility_version 3.5.0 \
  -Wl,-all_load "$PREFIX/lib/libssl.a" "$PREFIX/lib/libcrypto.a" \
  -o "$PREFIX/lib/libOpenSSL.dylib"
rm -f "$PREFIX/lib/libssl.a" "$PREFIX/lib/libcrypto.a"

for name in openssl libssl libcrypto; do
  cat > "$PREFIX/lib/pkgconfig/$name.pc" <<P
prefix=$PREFIX
Name: $name
Description: OpenSSL as one dylib
Version: $OPENSSL_VERSION
Libs: -L\${prefix}/lib -lOpenSSL
Cflags: -I\${prefix}/include
P
done
