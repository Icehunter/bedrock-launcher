#!/usr/bin/env bash
# Builds every launcher part, assembles the client bundle in out/bundle and
# wraps it in out/Bedrock Launcher.app.
# Stops at the first part that fails.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPTS/build-moltenvk.sh"
"$SCRIPTS/build-angle.sh"
"$SCRIPTS/build-client.sh"
"$SCRIPTS/build-mod.sh"
"$SCRIPTS/assemble-bundle.sh"
"$SCRIPTS/assemble-app.sh"
