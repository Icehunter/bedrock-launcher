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

This moves every fork's fix branch onto the newest upstream code, pushes it, and commits the new
submodule commits here. If a fix does not apply cleanly, the script stops, names the repo,
and pushes nothing for it. Fix that repo's branch by hand, then run the script again.

`SYNC_FORKS_ONLY=<repo>` syncs a single fork.
