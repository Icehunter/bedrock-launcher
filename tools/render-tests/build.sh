#!/usr/bin/env bash
# Builds render-tests with the ANGLE dylibs in out/angle.
# Usage: tools/render-tests/build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/tools/render-tests"
ANGLE="$ROOT/out/angle"
OUT="$ROOT/tools/render-tests/render-tests"

if [ ! -f "$ANGLE/libEGL.dylib" ] || [ ! -f "$ANGLE/libGLESv2.dylib" ]; then
  echo "build: missing $ANGLE/libEGL.dylib or libGLESv2.dylib; run scripts/build.sh first" >&2
  exit 1
fi

clang++ -ObjC++ -O1 -std=c++17 \
  -I"$ROOT/deps/angle/include" \
  -Wl,-rpath,"$ANGLE" \
  -L"$ANGLE" -lEGL -lGLESv2 \
  -framework Cocoa \
  -o "$OUT" \
  "$SRC/main.mm"

echo "build: $OUT"
