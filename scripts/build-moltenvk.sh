#!/usr/bin/env bash
# Builds MoltenVK from deps/MoltenVK into out/moltenvk/, for the macOS version
# in scripts/macos-min-version. Skips the build when out/moltenvk/.commit
# matches the submodule commit and that version.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/deps/MoltenVK"
OUT="$ROOT/out/moltenvk"
COMMIT="$(git -C "$SRC" rev-parse HEAD)"
MACOS_MIN="$(cat "$ROOT/scripts/macos-min-version")"
STAMP="$COMMIT macos-$MACOS_MIN"

if [ -f "$OUT/.commit" ] && [ "$(cat "$OUT/.commit")" = "$STAMP" ] \
  && [ -f "$OUT/libMoltenVK.dylib" ] && [ -f "$OUT/MoltenVK_icd.json" ]; then
  echo "build-moltenvk: up to date"
  exit 0
fi

export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
cd "$SRC"
./fetchDependencies --macos
make macos

PKG="$SRC/Package/Release/MoltenVK/dynamic/dylib/macOS"
mkdir -p "$OUT"
for f in libMoltenVK.dylib MoltenVK_icd.json; do
  rm -f "$OUT/$f"
  /bin/cp "$PKG/$f" "$OUT/$f"
done
echo "$STAMP" >"$OUT/.commit"
echo "build-moltenvk: built $COMMIT"
