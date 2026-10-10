#!/usr/bin/env bash
# Builds ANGLE's libEGL and libGLESv2 from deps/angle into out/angle/.
# Fetches depot_tools into .cache/ when missing, and ANGLE's third-party code
# with gclient. Skips the build when out/angle/.commit matches the submodule.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/deps/angle"
OUT="$ROOT/out/angle"
DEPOT="$ROOT/.cache/depot_tools"
COMMIT="$(git -C "$SRC" rev-parse HEAD)"

if [ -f "$OUT/.commit" ] && [ "$(cat "$OUT/.commit")" = "$COMMIT" ] \
  && [ -f "$OUT/libEGL.dylib" ] && [ -f "$OUT/libGLESv2.dylib" ]; then
  echo "build-angle: up to date"
  exit 0
fi

if [ ! -d "$DEPOT" ]; then
  git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT"
fi
if [ ! -f "$DEPOT/python3_bin_reldir.txt" ]; then
  "$DEPOT/ensure_bootstrap"
fi
export PATH="$DEPOT:$PATH"
export DEPOT_TOOLS_UPDATE=0

cd "$SRC"
if [ ! -f .gclient ]; then
  python3 scripts/bootstrap.py
fi
gclient sync -D --no-history
mkdir -p out/mac
/bin/cp "$ROOT/scripts/angle-args.gn" out/mac/args.gn
gn gen out/mac
autoninja -C out/mac libEGL libGLESv2

mkdir -p "$OUT"
for f in libEGL.dylib libGLESv2.dylib; do
  rm -f "$OUT/$f"
  /bin/cp "out/mac/$f" "$OUT/$f"
  # ANGLE builds these with a relative install name; give them a bundle-safe one.
  install_name_tool -id "@rpath/$f" "$OUT/$f"
done
echo "$COMMIT" >"$OUT/.commit"
echo "build-angle: built $COMMIT"
