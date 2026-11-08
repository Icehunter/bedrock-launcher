#!/usr/bin/env bash
# Takes the same arguments as scripts/run-bundle.sh.
# Set DYLD inside bash because macOS shells remove incoming DYLD variables.
set -euo pipefail
if [ "$#" -lt 3 ]; then
  echo 'usage: tools/gltrace/run.sh <bundle>/Contents <game-dir> <data-dir> [client args...]' >&2
  exit 2
fi
abs() { (cd "$1" && pwd); }
TRACE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTENTS="$(abs "$1")"
GAME="$(abs "$2")"
mkdir -p "$3"
DATA="$(abs "$3")"
shift 3
if [ ! -f "$TRACE_DIR/libgltrace.dylib" ]; then
  echo 'Build libgltrace.dylib first; see tools/gltrace/README.md' >&2
  exit 1
fi
mkdir -p "$DATA/cache"
export XDG_DATA_DIRS="$CONTENTS/Resources"
export PATH="$CONTENTS/MacOS:$PATH"
export DYLD_INSERT_LIBRARIES="$TRACE_DIR/libgltrace.dylib${DYLD_INSERT_LIBRARIES:+:$DYLD_INSERT_LIBRARIES}"
exec "$CONTENTS/MacOS/mcpelauncher-client" \
  -dg "$GAME" \
  -dd "$DATA" \
  -dc "$DATA/cache" \
  -m "$CONTENTS/Resources/mods/mcpelauncher-updates" \
  "$@"
