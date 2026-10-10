#!/usr/bin/env bash
# Lays out out/{client,gplay,angle,moltenvk,mod} as out/bundle/Contents/, in the same
# layout as the official launcher's app, ad-hoc signs every Mach-O file and
# checks the result with verify-bundle.sh.
#
# Files are removed before they are copied: overwriting a signed Mach-O in
# place gets the process killed when it loads the file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
C="$OUT/bundle/Contents"

place() {
  local from="$1" to="$2"
  mkdir -p "$(dirname "$to")"
  rm -f "$to"
  /bin/cp "$from" "$to"
}

place "$OUT/client/mcpelauncher-client" "$C/MacOS/mcpelauncher-client"
place "$OUT/gplay/bedrock-gplay" "$C/MacOS/bedrock-gplay"
for f in libEGL.dylib libGLESv2.dylib; do
  place "$OUT/angle/$f" "$C/Frameworks/mvk-angle/$f"
done
for f in libMoltenVK.dylib MoltenVK_icd.json; do
  place "$OUT/moltenvk/$f" "$C/Frameworks/mvk-angle/$f"
done
place "$OUT/client/gamecontrollerdb.txt" "$C/Resources/mcpelauncher/gamecontrollerdb.txt"
for f in "$OUT"/client/lib/arm64-v8a/*.so; do
  place "$f" "$C/Resources/mcpelauncher/lib/arm64-v8a/$(basename "$f")"
done
for f in "$OUT"/client/lib/native/arm64-v8a/*.dylib; do
  place "$f" "$C/Resources/mcpelauncher/lib/native/arm64-v8a/$(basename "$f")"
done

MOD="$C/Resources/mods/mcpelauncher-updates"
place "$OUT/mod/mcpelauncher-updates/libmcpelauncher-updates.so" "$MOD/libmcpelauncher-updates.so"
while IFS= read -r -d '' f; do
  place "$f" "$MOD/patches/${f#"$OUT/mod/mcpelauncher-updates/patches/"}"
done < <(find "$OUT/mod/mcpelauncher-updates/patches" -type f -print0)

while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q '^Mach-O'; then
    codesign --force -s - "$f"
  fi
done < <(find "$C" -type f -print0)

"$ROOT/scripts/verify-bundle.sh" "$C"
