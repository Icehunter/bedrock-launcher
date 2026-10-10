#!/usr/bin/env bash
# Builds mcpelauncher-client from deps/mcpelauncher-manifest into out/client/,
# with libcurl (websockets on) and OpenSSL linked in statically, plus the
# controller mapping file and the Android support libraries it loads.
#
# OpenSSL is built from source for the macOS version in
# scripts/macos-min-version, because Homebrew's static
# libraries target the macOS version of the machine that built them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/deps/mcpelauncher-manifest"
BUILD="$ROOT/out/build-client"
OUT="$ROOT/out/client"
MACOS_MIN="$(cat "$ROOT/scripts/macos-min-version")"
OPENSSL_VERSION="3.5.9"
OPENSSL_SHA256="603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a"
OPENSSL="$ROOT/.cache/openssl-$OPENSSL_VERSION-macos-$MACOS_MIN"

build_openssl() {
  [ -f "$OPENSSL/lib/libcrypto.a" ] && [ -f "$OPENSSL/lib/libssl.a" ] && return
  local tarball="$ROOT/.cache/openssl-$OPENSSL_VERSION.tar.gz"
  local src="$ROOT/.cache/openssl-$OPENSSL_VERSION-src"
  mkdir -p "$ROOT/.cache"
  if [ ! -f "$tarball" ]; then
    curl -fsSL -o "$tarball" \
      "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"
  fi
  if [ "$(shasum -a 256 "$tarball" | cut -d' ' -f1)" != "$OPENSSL_SHA256" ]; then
    echo "build-client: OpenSSL tarball checksum mismatch" >&2
    rm -f "$tarball"
    exit 1
  fi
  rm -rf "$src"
  mkdir -p "$src"
  tar -xzf "$tarball" -C "$src" --strip-components 1
  (
    cd "$src"
    export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
    ./Configure darwin64-arm64-cc no-shared no-tests no-docs --prefix="$OPENSSL" --libdir=lib
    make -j"$(sysctl -n hw.ncpu)"
    make install_sw
  )
  rm -rf "$src"
}

build_openssl

# The bundled curl is built as a separate project, so it gets the target twice:
# through CURL_EXT_EXTRA_OPTIONS and through the environment.
export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCURL_EXT_EXTRA_OPTIONS="-DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_MIN;-DCMAKE_OSX_ARCHITECTURES=arm64" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_UI=OFF \
  -DBUILD_WEBVIEW=OFF \
  -DENABLE_ERROR_WINDOW=OFF \
  -DXAL_WEBVIEW_USE_QT=ON \
  -DUSE_GAMECONTROLLERDB=ON \
  -DUSE_OWN_CURL=ON \
  -DENABLE_DEV_PATHS=OFF \
  -DOPENSSL_ROOT_DIR="$OPENSSL" \
  -DOPENSSL_USE_STATIC_LIBS=TRUE
cmake --build "$BUILD" --target mcpelauncher-client gamecontrollerdb

rm -rf "$OUT"
mkdir -p "$OUT/lib/arm64-v8a" "$OUT/lib/native/arm64-v8a"
/bin/cp "$BUILD/mcpelauncher-client/mcpelauncher-client" "$OUT/"
/bin/cp "$BUILD/gamecontrollerdb/gamecontrollerdb.txt" "$OUT/"
/bin/cp "$SRC"/mcpelauncher-mac-bin/lib/arm64-v8a/*.so "$OUT/lib/arm64-v8a/"
/bin/cp "$SRC"/mcpelauncher-mac-bin/lib/native/arm64-v8a/*.dylib "$OUT/lib/native/arm64-v8a/"
echo "build-client: built"
