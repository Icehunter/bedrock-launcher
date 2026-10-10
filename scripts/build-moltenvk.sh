#!/usr/bin/env bash
# Builds MoltenVK from deps/MoltenVK into out/moltenvk/.
# Skips the build when out/moltenvk/.commit matches the submodule commit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/deps/MoltenVK"
OUT="$ROOT/out/moltenvk"
COMMIT="$(git -C "$SRC" rev-parse HEAD)"

if [ -f "$OUT/.commit" ] && [ "$(cat "$OUT/.commit")" = "$COMMIT" ] \
  && [ -f "$OUT/libMoltenVK.dylib" ] && [ -f "$OUT/MoltenVK_icd.json" ]; then
  echo "build-moltenvk: up to date"
  exit 0
fi

export MACOSX_DEPLOYMENT_TARGET=14.0
cd "$SRC"
./fetchDependencies --macos
make macos

PKG="$SRC/Package/Release/MoltenVK/dynamic/dylib/macOS"
mkdir -p "$OUT"
for f in libMoltenVK.dylib MoltenVK_icd.json; do
  rm -f "$OUT/$f"
  /bin/cp "$PKG/$f" "$OUT/$f"
done
echo "$COMMIT" >"$OUT/.commit"
echo "build-moltenvk: built $COMMIT"
