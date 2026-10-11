#!/usr/bin/env bash
# Builds the Swift launcher and wraps it around the client bundle from
# assemble-bundle.sh, producing out/Bedrock Launcher.app, ad-hoc signed.
#
# The version is the git tag when HEAD is tagged (v1.2.3 gives 1.2.3), and
# "development" otherwise, which turns off the update check.
#
# Signing is done by sign-app.sh; SIGN_IDENTITY works the same way here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/out/Bedrock Launcher.app"
C="$APP/Contents"
MACOS_MIN="$(cat "$ROOT/scripts/macos-min-version")"

if [ ! -x "$ROOT/out/bundle/Contents/MacOS/mcpelauncher-client" ]; then
  echo "assemble-app: out/bundle is missing; run scripts/build.sh first" >&2
  exit 1
fi

(cd "$ROOT/mac" && swift build -c release --arch arm64)
BIN="$(cd "$ROOT/mac" && swift build -c release --arch arm64 --show-bin-path)"

if TAG="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null)"; then
  VERSION="${TAG#v}"
else
  VERSION="development"
fi
BUILD="$(git -C "$ROOT" rev-list --count HEAD)"

rm -rf "$APP"
mkdir -p "$C"
/bin/cp -R "$ROOT/out/bundle/Contents/." "$C/"
/bin/cp "$BIN/BedrockLauncher" "$C/MacOS/BedrockLauncher"
/bin/cp "$BIN/mcpelauncher-webview" "$C/MacOS/mcpelauncher-webview"
/bin/cp -R "$BIN/BedrockLauncher_BedrockLauncher.bundle" "$C/Resources/"
/bin/cp "$ROOT/mac/Sources/BedrockLauncher/Resources/AppIcon.icns" "$C/Resources/AppIcon.icns"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" -e "s/@MACOS_MIN@/$MACOS_MIN/" \
  "$ROOT/mac/Info.plist.in" >"$C/Info.plist"
plutil -lint "$C/Info.plist" >/dev/null

"$ROOT/scripts/sign-app.sh" "$APP"
echo "assemble-app: built $APP ($VERSION, build $BUILD)"
