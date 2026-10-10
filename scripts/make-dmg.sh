#!/usr/bin/env bash
# Packs out/Bedrock Launcher.app into out/Bedrock-Launcher.dmg: a disk image
# with the app next to a link to /Applications, to drag it across.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/out/Bedrock Launcher.app"
DMG="$ROOT/out/Bedrock-Launcher.dmg"

if [ ! -d "$APP" ]; then
  echo "make-dmg: $APP is missing; run scripts/build.sh first" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
/bin/cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "Bedrock Launcher" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
hdiutil verify -quiet "$DMG"
echo "make-dmg: built $DMG ($(du -h "$DMG" | cut -f1))"
