# Bedrock Launcher for macOS

Runs Minecraft Bedrock on Apple Silicon Macs. It is built on the
[minecraft-linux](https://github.com/minecraft-linux) launcher, with fixes for macOS kept in
forks under this account.

The game itself is not in this repo. Each player downloads it from Google Play with their own
account.

## Getting the source

```sh
git clone https://github.com/Icehunter/bedrock-launcher.git
cd bedrock-launcher
git submodule update --init --depth 1 deps/angle deps/MoltenVK
git submodule update --init --recursive deps/mcpelauncher-manifest deps/mcpelauncher-updates
```

Do not clone with `--recurse-submodules`. ANGLE lists Chromium submodules, some of which need a
Google account. The ANGLE build fetches its own third-party code with `gclient` instead.

The launcher parts live in `deps/`:

| Folder | Repo | Branch |
|---|---|---|
| `deps/mcpelauncher-manifest` | Icehunter/mcpelauncher-manifest | `bedrock-macos` |
| `deps/mcpelauncher-updates` | Icehunter/mcpelauncher-updates | `bedrock-macos` |
| `deps/angle` | Icehunter/angle | `fix/moltenvk-macos-gles31-support` |
| `deps/MoltenVK` | Icehunter/MoltenVK | `fix/vulkan-integer-float-format-mismatch` |

`deps/mcpelauncher-manifest` has its own submodules. Four of them come from Icehunter forks on
the `bedrock-macos` branch: `libc-shim`, `minecraft-imported-symbols`, `mcpelauncher-core` and
`mcpelauncher-client`. The rest come straight from upstream.

## Keeping up with upstream

```sh
scripts/sync-forks.sh
```

This moves every fork's fix branch onto the newest upstream code and rebuilds the
`mcpelauncher-manifest` fix branch on top of upstream, pointing it at the new fork commits. Then
it commits the new submodule commits here; push them when ready.

The script rebases every fork first and pushes only if all of them rebase cleanly. If one does
not, it names the repo and pushes nothing. Fix that repo's branch by hand, then run the script
again. Before a branch is replaced, its old commit is kept under a
`bedrock-macos-archive/<time>/<branch>` tag, so older checkouts of this repo can still fetch it.

| Setting | Effect |
|---|---|
| `SYNC_FORKS_ONLY="repo ..."` | Sync only these forks. Submodule commits here are not updated. |
| `SYNC_FORKS_BRANCH="repo=branch ..."` | Use another branch for these forks. |
| `SYNC_FORKS_DRY_RUN=1` | Do everything except push, and show what would change. |
