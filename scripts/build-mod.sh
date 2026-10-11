#!/usr/bin/env bash
# Builds the mcpelauncher-updates mod (arm64) from deps/mcpelauncher-updates
# into out/mod/mcpelauncher-updates/, with the patches/ folder from upstream's
# v26.40.1 release (replacement libPlayFabMultiplayer.so and libmaesdk.so).
#
# Needs the Android NDK: ANDROID_NDK_ROOT, else the Android Studio default.
# Skips the build when the mod's commit, the NDK and the patches zip are the
# same as last time (recorded in out/mod/mcpelauncher-updates/.commit).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/deps/mcpelauncher-updates"
OUT="$ROOT/out/mod/mcpelauncher-updates"
NDK="${ANDROID_NDK_ROOT:-$HOME/Library/Android/sdk/ndk/30.0.16248370}"
PATCHES_URL="https://github.com/minecraft-linux/mcpelauncher-updates/releases/download/v26.40.1/mcpelauncher-updates-arm64-release.zip"
PATCHES_SHA256="5e3050816ba49c6a94dc119ccd5d38a3fd8fb2924da511bfb1b63a5bffd5c880"
PATCHES_ZIP="$ROOT/.cache/mcpelauncher-updates-v26.40.1-arm64.zip"

if [ ! -f "$NDK/build/cmake/android.toolchain.cmake" ]; then
  echo "build-mod: Android NDK not found at $NDK; set ANDROID_NDK_ROOT" >&2
  exit 1
fi

mkdir -p "$ROOT/.cache"
if [ ! -f "$PATCHES_ZIP" ]; then
  curl -fsSL -o "$PATCHES_ZIP" "$PATCHES_URL"
fi
if [ "$(shasum -a 256 "$PATCHES_ZIP" | cut -d' ' -f1)" != "$PATCHES_SHA256" ]; then
  echo "build-mod: patches zip checksum mismatch" >&2
  exit 1
fi

COMMIT="$(git -C "$SRC" rev-parse HEAD)"
STAMP="$COMMIT ndk-$(basename "$NDK") patches-$PATCHES_SHA256"
if [ -f "$OUT/libmcpelauncher-updates.so" ] && [ "$(cat "$OUT/.commit" 2>/dev/null)" = "$STAMP" ]; then
  echo "build-mod: up to date"
  exit 0
fi

PROTOC_BUILD="$ROOT/out/build-mod/protoc"
MOD_BUILD="$ROOT/out/build-mod/arm64"
cmake -S "$SRC/protobuf" -B "$PROTOC_BUILD" -DCMAKE_BUILD_TYPE=Release \
  -Dprotobuf_BUILD_TESTS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$PROTOC_BUILD" --parallel --target protoc
cmake -S "$SRC" -B "$MOD_BUILD" \
  -DANDROID_PLATFORM=21 -DANDROID_ABI=arm64-v8a \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DProtobuf_PROTOC_EXECUTABLE="$PROTOC_BUILD/protoc" \
  -DProtobuf_INCLUDE_DIR="$SRC/protobuf/src" \
  -DCMAKE_BUILD_TYPE=Release \
  -DMCPELAUNCHER_UPDATES_VALIDATE=OFF \
  -DMCPELAUNCHER_UPDATES_STANDALONE=ON
cmake --build "$MOD_BUILD" --parallel

UNPACK="$ROOT/out/build-mod/patches-zip"
rm -rf "$UNPACK" "$OUT"
mkdir -p "$UNPACK" "$OUT"
unzip -q "$PATCHES_ZIP" -d "$UNPACK"
/bin/cp "$MOD_BUILD/libmcpelauncher-updates.so" "$OUT/"
/bin/cp -R "$UNPACK/patches" "$OUT/patches"
echo "$STAMP" >"$OUT/.commit"
echo "build-mod: built $COMMIT"
