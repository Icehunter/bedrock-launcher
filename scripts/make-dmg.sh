#!/usr/bin/env bash
# Packs out/Bedrock Launcher.app into out/Bedrock-Launcher.dmg: a disk image
# with the app next to a link to /Applications, to drag it across.
#
# SIGN_IDENTITY signs the disk image with that certificate. To notarize it,
# set NOTARY_PROFILE to a profile saved with `xcrun notarytool
# store-credentials`, or set NOTARY_KEY_FILE, NOTARY_KEY_ID and
# NOTARY_ISSUER_ID to an App Store Connect API key. Notarized images get the
# ticket stapled, so they open without a network check.
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

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force -s "$SIGN_IDENTITY" --timestamp "$DMG"
fi

NOTARY=()
if [ -n "${NOTARY_PROFILE:-}" ]; then
  NOTARY=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${NOTARY_KEY_FILE:-}" ]; then
  NOTARY=(--key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
fi
if [ ${#NOTARY[@]} -gt 0 ]; then
  echo "make-dmg: sending to Apple for notarization; this takes a few minutes"
  xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait --output-format json >"$ROOT/out/notarization.json"
  STATUS="$(plutil -extract status raw "$ROOT/out/notarization.json")"
  if [ "$STATUS" != "Accepted" ]; then
    ID="$(plutil -extract id raw "$ROOT/out/notarization.json")"
    echo "make-dmg: notarization $STATUS; details: xcrun notarytool log $ID ${NOTARY[*]}" >&2
    exit 1
  fi
  xcrun stapler staple -q "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

echo "make-dmg: built $DMG ($(du -h "$DMG" | cut -f1))"
