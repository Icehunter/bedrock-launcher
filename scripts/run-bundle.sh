#!/usr/bin/env bash
# Starts the game from a client bundle. The launcher app starts it the same way.
#
# Usage: scripts/run-bundle.sh <bundle>/Contents <game-dir> <data-dir> [client args...]
#
# <game-dir> holds the unpacked APK; <data-dir> holds worlds, settings and the
# Xbox sign-in. Both are made absolute: a relative data folder is resolved
# against the game's assets and the saved sign-in is not found.
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "usage: run-bundle.sh <bundle>/Contents <game-dir> <data-dir> [client args...]" >&2
  exit 2
fi

abs() { (cd "$1" && pwd); }

CONTENTS="$(abs "$1")"
GAME="$(abs "$2")"
mkdir -p "$3"
DATA="$(abs "$3")"
shift 3

mkdir -p "$DATA/cache"
export XDG_DATA_DIRS="$CONTENTS/Resources"
export PATH="$CONTENTS/MacOS:$PATH"

exec "$CONTENTS/MacOS/mcpelauncher-client" \
  -dg "$GAME" \
  -dd "$DATA" \
  -dc "$DATA/cache" \
  -m "$CONTENTS/Resources/mods/mcpelauncher-updates" \
  "$@"
