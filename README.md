# Bedrock Launcher for macOS

Runs Minecraft Bedrock on Apple Silicon Macs. It is built on the
[minecraft-linux](https://github.com/minecraft-linux) launcher, with fixes for macOS kept in
forks under this account.

The game itself is not in this repo. Each player downloads it from Google Play with their own
account.

## Using the launcher

The launcher has these pages:

- Play: pick a profile and start the game.
- Content: install `.mcpack`, `.mcaddon` and `.mcworld` files, open `minecraft://` links, open
  the game folders, link pack folders you are working on, and see the pack errors from the last
  run.
- Versions: get the game, and export, import or delete game versions.
- Game Log: the game's output while it runs.
- Settings: launcher options.

## Getting the game

The game comes from Google Play, through your own Google account. There are two ways to get it:

- Download: on the Versions page, pick a version and click Download from Google Play. The
  launcher asks you to sign in to Google the first time. It only offers versions it is tested
  with, listed in `tested-versions.json`.
- Import: click Import Files and pick either the APK files Google Play gives for one version, or
  a `.mcversion` file.

Export, next to each installed version, saves it as one `.mcversion` file. Copy that file to
another Mac and import it there, for example to set up a child's Mac without signing in to Google
on it. Google sign-in is only needed for Download. Settings has the sign out button.

A red bar at the top means Google Play has a newer Minecraft than the launcher is tested with.
Downloads stay on the newest tested version until the launcher is updated.

Download the `.dmg` from the [Releases](https://github.com/Icehunter/bedrock-launcher/releases)
page, open it and drag Bedrock Launcher to Applications. Releases are signed with a Developer ID
and notarized by Apple, so macOS opens them without a warning. It needs an Apple Silicon Mac with
macOS 15 or newer.

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

The bundle runs on every macOS release Apple still sends security updates to, and no older
one. `scripts/macos-min-version` holds the oldest such release; raise it when Apple stops
updating that release, and every part is rebuilt for the new version.

Building needs an Apple Silicon Mac with:

- Xcode (from the App Store), opened once so it finishes setting up
- [Homebrew](https://brew.sh), then `brew install cmake ninja python3`
- Android NDK 30.0.16248370, from Android Studio's SDK Manager or
  `sdkmanager "ndk;30.0.16248370"`. If it is not in the Android Studio default folder, set
  `ANDROID_NDK_ROOT` to it.

Get the source as above, then:

```sh
scripts/build.sh
```

This builds MoltenVK, ANGLE, the game client, the updates mod and the launcher, then puts them
together as `out/Bedrock Launcher.app` and checks the result. The first build takes about an hour, most of it
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

## License

Bedrock Launcher is free software under the GNU General Public License, version 3. See
[LICENSE](LICENSE).

The app ships these parts, each under its own license:

| Part | License |
|---|---|
| mcpelauncher client and its libraries (minecraft-linux) | GPL-3.0 |
| mcpelauncher-updates | MIT |
| Google-Play-API | Apache-2.0 |
| ANGLE | BSD-3-Clause |
| MoltenVK | Apache-2.0 |
| OpenSSL | Apache-2.0 |
| curl | curl license (MIT style) |
| protobuf | BSD-3-Clause |

The source for every part is in this repo and the forks it links to under `deps/`.

Minecraft is a trademark of Mojang Synergies AB. This project is not made by, or connected to,
Mojang or Microsoft. The game is not included; each player gets it from Google Play with their own
account.
