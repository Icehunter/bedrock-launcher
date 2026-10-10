#!/usr/bin/env bash
# Checks a client bundle: every expected file is there, every Mach-O file
# links only system libraries or paths inside the bundle, needs no macOS
# newer than scripts/macos-min-version, is arm64 and has a valid signature, and no game file is
# included.
#
# Usage: scripts/verify-bundle.sh <bundle>/Contents
set -uo pipefail

CONTENTS="${1:?usage: verify-bundle.sh <bundle>/Contents}"
MAX_MINOS="$(cat "$(cd "$(dirname "$0")" && pwd)/macos-min-version")"
failed=0

fail() {
  echo "verify-bundle: $*"
  failed=1
}

EXPECTED=(
  MacOS/mcpelauncher-client
  MacOS/bedrock-gplay
  Frameworks/mvk-angle/libEGL.dylib
  Frameworks/mvk-angle/libGLESv2.dylib
  Frameworks/mvk-angle/libMoltenVK.dylib
  Frameworks/mvk-angle/MoltenVK_icd.json
  Resources/mcpelauncher/gamecontrollerdb.txt
  Resources/mcpelauncher/lib/arm64-v8a/libc.so
  Resources/mcpelauncher/lib/arm64-v8a/libjnivmsupport.so
  Resources/mcpelauncher/lib/arm64-v8a/liblog.so
  Resources/mcpelauncher/lib/arm64-v8a/libsqliteX.so
  Resources/mcpelauncher/lib/native/arm64-v8a/libfmod.dylib
  Resources/mods/mcpelauncher-updates/libmcpelauncher-updates.so
  Resources/mods/mcpelauncher-updates/patches/libPlayFabMultiplayer.so
  Resources/mods/mcpelauncher-updates/patches/v1.26.0.2/arm64-v8a/libmaesdk.so
)

# A finished app also carries the launcher itself and the sign-in helper.
case "$CONTENTS" in
  *.app/Contents | *.app/Contents/)
    EXPECTED+=(
      MacOS/BedrockLauncher
      MacOS/mcpelauncher-webview
      Info.plist
      Resources/AppIcon.icns
      Resources/BedrockLauncher_BedrockLauncher.bundle
    )
    ;;
esac

for f in "${EXPECTED[@]}"; do
  [ -e "$CONTENTS/$f" ] || fail "missing $f"
done

# Version strings like 15.0 or 14.5.1: true when $1 is newer than $2.
version_gt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

while IFS= read -r -d '' f; do
  file -b "$f" | grep -q '^Mach-O' || continue
  rel="${f#"$CONTENTS"/}"

  while read -r dep; do
    case "$dep" in
      /usr/lib/* | /System/* | @rpath/* | @loader_path/* | @executable_path/*) ;;
      *) fail "$rel links $dep" ;;
    esac
  done < <(otool -L "$f" | grep -v ':$' | awk '{print $1}')

  # One value per architecture slice; universal files have several.
  minos_list="$(otool -arch all -l "$f" | awk '
    /LC_BUILD_VERSION/ {b=1; next}
    /LC_VERSION_MIN_MACOSX/ {v=1; next}
    b && $1=="minos" {print $2; b=0}
    v && $1=="version" {print $2; v=0}')"
  if [ -z "$minos_list" ]; then
    fail "$rel has no minimum macOS version"
  fi
  for minos in $minos_list; do
    if version_gt "$minos" "$MAX_MINOS"; then
      fail "$rel needs macOS $minos, newer than $MAX_MINOS"
    fi
  done

  lipo -archs "$f" 2>/dev/null | grep -qw arm64 || fail "$rel is not arm64"
  codesign --verify "$f" 2>/dev/null || fail "$rel has no valid signature"
done < <(find "$CONTENTS" -type f -print0)

while IFS= read -r -d '' f; do
  fail "game file found: ${f#"$CONTENTS"/}"
done < <(find "$CONTENTS" \( -name 'libminecraftpe.so' -o -name '*.apk' \) -print0)

if [ "$failed" = 0 ]; then
  echo "verify-bundle: ok"
fi
exit "$failed"
