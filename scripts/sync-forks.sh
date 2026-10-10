#!/usr/bin/env bash
# Moves every fork's fix branch onto the newest upstream code, rebuilds the
# mcpelauncher-manifest fix branch on top of upstream, and points
# bedrock-launcher at the new commits.
#
# Runs in two phases. First every fork is rebased in a temp folder. Only if
# every rebase works does anything get pushed, so one conflict leaves every
# fork as it was. Before a branch is replaced, its old tip is kept under a
# bedrock-macos-archive/<time>/<branch> tag, so older pins stay fetchable.
#
# Settings:
#   SYNC_FORKS_ONLY="repo ..."         sync only these forks
#   SYNC_FORKS_BRANCH="repo=branch ..." use another branch for these forks
#   SYNC_FORKS_DRY_RUN=1               do every step except pushing
#
# Needs: git, gh (logged in as the fork owner).
set -euo pipefail

OWNER="${SYNC_FORKS_OWNER:-Icehunter}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FIX_BRANCH="bedrock-macos"

# repo name, upstream owner/repo, fix branch
FORKS=(
  "libc-shim minecraft-linux/libc-shim bedrock-macos"
  "minecraft-imported-symbols minecraft-linux/minecraft-imported-symbols bedrock-macos"
  "mcpelauncher-core minecraft-linux/mcpelauncher-core bedrock-macos"
  "mcpelauncher-client minecraft-linux/mcpelauncher-client bedrock-macos"
  "mcpelauncher-updates minecraft-linux/mcpelauncher-updates bedrock-macos"
  "angle google/angle fix/moltenvk-macos-gles31-support"
  "MoltenVK KhronosGroup/MoltenVK fix/vulkan-integer-float-format-mismatch"
)

# Manifest submodules that come from the forks above. Every other relative
# submodule URL is pointed at minecraft-linux.
MANIFEST_UPSTREAM="minecraft-linux/mcpelauncher-manifest"
MANIFEST_FORKS=(libc-shim minecraft-imported-symbols mcpelauncher-core mcpelauncher-client)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { echo "sync-forks: $*"; }

selected() {
  [ -z "${SYNC_FORKS_ONLY:-}" ] && return 0
  [[ " $SYNC_FORKS_ONLY " == *" $1 "* ]]
}

branch_for() {
  local name="$1" default="$2" pair
  for pair in ${SYNC_FORKS_BRANCH:-}; do
    if [ "${pair%%=*}" = "$name" ]; then
      echo "${pair#*=}"
      return
    fi
  done
  echo "$default"
}

# Phase 1: rebase into $WORK/<name>. Exits on the first conflict, before any push.
rebase_fork() {
  local name="$1" upstream="$2" branch="$3"
  local dir="$WORK/$name" upstream_branch
  upstream_branch="$(gh api "repos/$upstream" --jq .default_branch)"
  say "$name: rebasing $branch onto $upstream $upstream_branch"
  git clone -q --filter=blob:none -b "$branch" "https://github.com/$OWNER/$name.git" "$dir"
  git -C "$dir" remote add upstream "https://github.com/$upstream.git"
  git -C "$dir" fetch -q --filter=blob:none upstream "$upstream_branch"
  git -C "$dir" rev-parse HEAD >"$dir.old"
  if ! git -C "$dir" rebase -q "upstream/$upstream_branch"; then
    git -C "$dir" rebase --abort || true
    say "$name needs a manual rebase; nothing was pushed" >&2
    exit 1
  fi
}

# Rebuilds the manifest fix branch from upstream: absolute submodule URLs, the
# forked submodules on their fix branch, and their pins at the new fork tips.
rebuild_manifest() {
  local dir="$WORK/mcpelauncher-manifest" upstream_branch
  upstream_branch="$(gh api "repos/$MANIFEST_UPSTREAM" --jq .default_branch)"
  say "mcpelauncher-manifest: rebuilding $FIX_BRANCH from $MANIFEST_UPSTREAM $upstream_branch"
  git clone -q --filter=blob:none -b "$FIX_BRANCH" "https://github.com/$OWNER/mcpelauncher-manifest.git" "$dir"
  git -C "$dir" rev-parse HEAD >"$dir.old"
  git -C "$dir" fetch -q --filter=blob:none "https://github.com/$MANIFEST_UPSTREAM.git" "$upstream_branch"
  git -C "$dir" reset -q --hard FETCH_HEAD

  local key path url
  while read -r key url; do
    path="${key#submodule.}"
    path="${path%.url}"
    case "$url" in
      ../../*) url="https://github.com/${url#../../}" ;;
      ../*) url="https://github.com/minecraft-linux/${url#../}" ;;
    esac
    git -C "$dir" config -f .gitmodules "submodule.$path.url" "$url"
  done < <(git -C "$dir" config -f .gitmodules --get-regexp '^submodule\..*\.url$')

  local sub tip
  for sub in "${MANIFEST_FORKS[@]}"; do
    git -C "$dir" config -f .gitmodules "submodule.$sub.url" "https://github.com/$OWNER/$sub.git"
    git -C "$dir" config -f .gitmodules "submodule.$sub.branch" "$FIX_BRANCH"
    if [ -d "$WORK/$sub" ]; then
      tip="$(git -C "$WORK/$sub" rev-parse HEAD)"
    else
      tip="$(git ls-remote "https://github.com/$OWNER/$sub.git" "refs/heads/$FIX_BRANCH" | cut -f1)"
    fi
    if [ -z "$tip" ]; then
      say "no $FIX_BRANCH branch found for $sub; nothing was pushed" >&2
      exit 1
    fi
    git -C "$dir" update-index --cacheinfo "160000,$tip,$sub"
  done
  git -C "$dir" add .gitmodules
  git -C "$dir" commit -q -m "macos: point submodules at the macOS fix branches"
  # Same files as the current branch: keep the current commit, so nothing is pushed.
  if git -C "$dir" diff --quiet "$(cat "$dir.old")" HEAD; then
    git -C "$dir" reset -q --hard "$(cat "$dir.old")"
  fi
}

# Phase 2: keep the old tip under a tag, then replace the branch.
push_fork() {
  local name="$1" branch="$2" dir="$WORK/$1" old
  old="$(cat "$dir.old")"
  if [ "$old" = "$(git -C "$dir" rev-parse HEAD)" ]; then
    say "$name: already current"
    return
  fi
  if [ -n "${SYNC_FORKS_DRY_RUN:-}" ]; then
    say "$name: would push $branch $(git -C "$dir" rev-parse --short HEAD) (dry run)"
    git -C "$dir" diff --stat "$old" HEAD | sed "s/^/sync-forks:   /"
    return
  fi
  git -C "$dir" push -q origin "$old:refs/tags/bedrock-macos-archive/$STAMP/$branch"
  git -C "$dir" push -q --force-with-lease="$branch:$old" origin "HEAD:$branch"
  say "$name: pushed $branch $(git -C "$dir" rev-parse --short HEAD)"
}

PLANNED=()
for entry in "${FORKS[@]}"; do
  read -r name upstream branch <<<"$entry"
  selected "$name" || continue
  branch="$(branch_for "$name" "$branch")"
  rebase_fork "$name" "$upstream" "$branch"
  PLANNED+=("$name $branch")
done
if selected mcpelauncher-manifest; then
  rebuild_manifest
  PLANNED+=("mcpelauncher-manifest $FIX_BRANCH")
fi

for entry in "${PLANNED[@]}"; do
  read -r name branch <<<"$entry"
  push_fork "$name" "$branch"
done

if [ -z "${SYNC_FORKS_ONLY:-}" ] && [ -z "${SYNC_FORKS_DRY_RUN:-}" ]; then
  git -C "$ROOT" submodule update -q --remote deps/mcpelauncher-manifest deps/mcpelauncher-updates deps/angle deps/MoltenVK
  git -C "$ROOT" submodule update -q --init --recursive deps/mcpelauncher-manifest
  if ! git -C "$ROOT" diff --quiet -- deps; then
    git -C "$ROOT" commit -q -m "deps: sync with upstream" -- deps
    say "committed new submodule commits in bedrock-launcher; push when ready"
  fi
fi

say "done"
