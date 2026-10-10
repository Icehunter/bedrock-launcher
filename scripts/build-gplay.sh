#!/usr/bin/env bash
# Builds bedrock-gplay, the launcher's Google Play helper, into out/gplay/.
#
# protobuf is built from source as static libraries for the macOS version in
# scripts/macos-min-version. libcurl and OpenSSL come from build-client.sh, so
# that runs first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/out/build-gplay"
OUT="$ROOT/out/gplay"
MACOS_MIN="$(cat "$ROOT/scripts/macos-min-version")"
PROTOBUF_VERSION="3.21.12"
PROTOBUF_SHA256="4eab9b524aa5913c6fffb20b2a8abf5ef7f95a80bc0701f3a6dbb4c607f73460"
PROTOBUF="$ROOT/.cache/protobuf-21.12-macos-$MACOS_MIN"
OPENSSL="$ROOT/.cache/openssl-3.5.9-macos-$MACOS_MIN"
CURL="$ROOT/out/build-client/ext/curl"

if [ ! -f "$CURL/lib/libcurl.a" ] || [ ! -f "$OPENSSL/lib/libssl.a" ]; then
  echo "build-gplay: libcurl or OpenSSL is missing; run scripts/build-client.sh first" >&2
  exit 1
fi

build_protobuf() {
  [ -f "$PROTOBUF/lib/libprotobuf.a" ] && [ -x "$PROTOBUF/bin/protoc" ] && return
  local tarball="$ROOT/.cache/protobuf-cpp-$PROTOBUF_VERSION.tar.gz"
  local src="$ROOT/.cache/protobuf-$PROTOBUF_VERSION-src"
  mkdir -p "$ROOT/.cache"
  if [ ! -f "$tarball" ]; then
    curl -fsSL -o "$tarball" \
      "https://github.com/protocolbuffers/protobuf/releases/download/v21.12/protobuf-cpp-$PROTOBUF_VERSION.tar.gz"
  fi
  if [ "$(shasum -a 256 "$tarball" | cut -d' ' -f1)" != "$PROTOBUF_SHA256" ]; then
    echo "build-gplay: protobuf tarball checksum mismatch" >&2
    rm -f "$tarball"
    exit 1
  fi
  rm -rf "$src"
  mkdir -p "$src"
  tar -xzf "$tarball" -C "$src" --strip-components 1
  cmake -S "$src" -B "$src/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_INSTALL_PREFIX="$PROTOBUF" \
    -Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_BUILD_SHARED_LIBS=OFF \
    -Dprotobuf_WITH_ZLIB=OFF
  cmake --build "$src/build" --target install
  rm -rf "$src"
}

build_protobuf

export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
cmake -S "$ROOT/tools/gplay" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_PREFIX_PATH="$PROTOBUF;$CURL" \
  -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON \
  -Dprotobuf_MODULE_COMPATIBLE=ON \
  -DOPENSSL_ROOT_DIR="$OPENSSL" \
  -DOPENSSL_USE_STATIC_LIBS=TRUE
cmake --build "$BUILD" --target bedrock-gplay

rm -rf "$OUT"
mkdir -p "$OUT"
/bin/cp "$BUILD/bedrock-gplay" "$OUT/"
echo "build-gplay: built"
