#!/usr/bin/env bash
# Signs a built Bedrock Launcher.app and checks it.
#
# Usage: sign-app.sh <path/to/Bedrock Launcher.app>
#
# SIGN_IDENTITY picks the signing certificate, for example
# "Developer ID Application: Ryan Wilson (HVY78N7EUW)". Unset, the app is
# ad-hoc signed. A real identity also turns on the hardened runtime, with the
# exceptions in mac/client.entitlements for the game client.
#
# APP_VERSION, when set, is written into Info.plist first. Release builds use
# it to stamp the version tag on an app built from the same commit on main.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?usage: sign-app.sh <app>}"
C="$APP/Contents"

if [ -n "${APP_VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$C/Info.plist"
fi

IDENTITY="${SIGN_IDENTITY:--}"
SIGN=(codesign --force -s "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then
  SIGN+=(--options runtime --timestamp)
fi

# Sign every Mach-O file first, then the app as a whole. macOS treats every
# file under Frameworks as code, so the MoltenVK JSON there is signed too
# (its signature goes in extended attributes). The app's main executable is
# left for last: codesign given that file signs the whole app, which fails
# while other files inside are still unsigned.
while IFS= read -r -d '' f; do
  [ "$f" = "$C/MacOS/BedrockLauncher" ] && continue
  if file -b "$f" | grep -q '^Mach-O' || [[ "$f" == "$C/Frameworks/"* ]]; then
    if [ "$f" = "$C/MacOS/mcpelauncher-client" ] && [ "$IDENTITY" != "-" ]; then
      "${SIGN[@]}" --entitlements "$ROOT/mac/client.entitlements" "$f"
    else
      "${SIGN[@]}" "$f"
    fi
  fi
done < <(find "$C" -type f -print0)
"${SIGN[@]}" "$APP"

"$ROOT/scripts/verify-bundle.sh" "$C"
codesign --verify --deep --strict "$APP"
# The app must find its images inside itself, not in this Mac's build folder.
BEDROCK_RESOURCES_STRICT=1 "$C/MacOS/BedrockLauncher" --check-resources
echo "sign-app: signed $APP ($(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$C/Info.plist"))"
