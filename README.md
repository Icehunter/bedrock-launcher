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

## Building

Needs an Apple Silicon Mac with:

- Xcode (from the App Store), opened once so it finishes setting up
- [Homebrew](https://brew.sh), then `brew install cmake ninja python3`
- Android NDK 30.0.16248370, from Android Studio's SDK Manager or
  `sdkmanager "ndk;30.0.16248370"`. If it is not in the Android Studio default folder, set
  `ANDROID_NDK_ROOT` to it.

Get the source as above, then:

```sh
scripts/build.sh
```

This builds MoltenVK, ANGLE, the game client and the updates mod, then puts them together in
`out/bundle/Contents` and checks the result. The first build takes about an hour, most of it
ANGLE. Later builds skip MoltenVK and ANGLE when their source has not changed.

To start the game from the bundle, with an unpacked game folder and a folder for worlds and
settings:

```sh
scripts/run-bundle.sh out/bundle/Contents /path/to/game /path/to/data
```

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
