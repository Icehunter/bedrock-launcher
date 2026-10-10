#!/usr/bin/env bash
# Moves every fork's fix branch onto the newest upstream code, then points
# mcpelauncher-manifest and bedrock-launcher at the new commits.
#
# Stops on the first rebase conflict and pushes nothing for that repo.
# Set SYNC_FORKS_ONLY=<repo> to sync a single fork, and SYNC_FORKS_BRANCH=<branch>
# with it to sync a branch other than the fix branch.
#
# Needs: git, gh (logged in as the fork owner).
set -euo pipefail

OWNER="${SYNC_FORKS_OWNER:-Icehunter}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# repo name, upstream owner/repo, fix branch
FORKS=(
  "libc-shim minecraft-linux/libc-shim bedrock-macos"
  "minecraft-imported-symbols minecraft-linux/minecraft-imported-symbols bedrock-macos"
  "mcpelauncher-core minecraft-linux/mcpelauncher-core bedrock-macos"
  "mcpelauncher-client minecraft-linux/mcpelauncher-client bedrock-macos"
  "mcpelauncher-updates minecraft-linux/mcpelauncher-updates bedrock-macos"
  "angle google/angle fix/moltenvk-macos-gles31-support"
  "MoltenVK KhronosGroup/MoltenVK fix/vulkan-integer-float-format-mismatch"
  "mcpelauncher-manifest minecraft-linux/mcpelauncher-manifest bedrock-macos"
)

# Submodules inside the manifest that come from the forks above.
MANIFEST_FORKS=(libc-shim minecraft-imported-symbols mcpelauncher-core mcpelauncher-client)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rebase_fork() {
  local name="$1" upstream="$2" branch="$3"
  local dir="$WORK/$name"
  local upstream_branch
  upstream_branch="$(gh api "repos/$upstream" --jq .default_branch)"

  echo "sync-forks: $name: rebasing $branch onto $upstream $upstream_branch"
  git clone -q --filter=blob:none -b "$branch" "https://github.com/$OWNER/$name.git" "$dir"
  git -C "$dir" remote add upstream "https://github.com/$upstream.git"
  git -C "$dir" fetch -q --filter=blob:none upstream "$upstream_branch"

  if ! git -C "$dir" rebase -q "upstream/$upstream_branch"; then
    git -C "$dir" rebase --abort
    echo "sync-forks: $name needs a manual rebase" >&2
    exit 1
  fi
}

push_fork() {
  local name="$1" branch="$2"
  git -C "$WORK/$name" push -q --force-with-lease origin "$branch"
}

point_manifest_at_forks() {
  local dir="$WORK/mcpelauncher-manifest"
  local changed=0
  for sub in "${MANIFEST_FORKS[@]}"; do
    local tip
    tip="$(git ls-remote "https://github.com/$OWNER/$sub.git" refs/heads/bedrock-macos | cut -f1)"
    if [ "$(git -C "$dir" ls-tree HEAD "$sub" | awk '{print $3}')" != "$tip" ]; then
      git -C "$dir" update-index --cacheinfo "160000,$tip,$sub"
      changed=1
    fi
  done
  if [ "$changed" = 1 ]; then
    git -C "$dir" commit -q -m "deps: sync with upstream"
  fi
}

for entry in "${FORKS[@]}"; do
  read -r name upstream branch <<<"$entry"
  if [ -n "${SYNC_FORKS_ONLY:-}" ] && [ "$SYNC_FORKS_ONLY" != "$name" ]; then
    continue
  fi
  if [ -n "${SYNC_FORKS_ONLY:-}" ] && [ -n "${SYNC_FORKS_BRANCH:-}" ]; then
    branch="$SYNC_FORKS_BRANCH"
  fi
  rebase_fork "$name" "$upstream" "$branch"
  if [ "$name" = "mcpelauncher-manifest" ]; then
    point_manifest_at_forks
  fi
  push_fork "$name" "$branch"
done

if [ -z "${SYNC_FORKS_ONLY:-}" ]; then
  git -C "$ROOT" submodule update -q --remote deps/mcpelauncher-manifest deps/mcpelauncher-updates deps/angle deps/MoltenVK
  if ! git -C "$ROOT" diff --quiet -- deps; then
    git -C "$ROOT" add deps
    git -C "$ROOT" commit -q -m "deps: sync with upstream"
    echo "sync-forks: committed new submodule commits in bedrock-launcher; push when ready"
  fi
fi

echo "sync-forks: done"
