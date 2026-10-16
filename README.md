# GameWrap

![Solarpunk gaming garden](assets/solarpunk.png)

**Turn Windows games into Mac apps.**

GameWrap turns a Windows game folder, `.exe`, `.zip`, `.rar`, or `.7z` into a double-clickable Mac app, with an optional DMG. A native, single-screen interface helps you choose the program, customize its icon, and build a self-contained app using Wine and D3DMetal.

**Status: early preview.** Building an app does not guarantee that its game will run. Compatibility depends on the game, your Mac, and the bundled runtime. Anti-cheat, DRM, launchers, and some graphics features may prevent a game from working.

## Requirements

- Apple silicon Mac running macOS 14 or later
- Rosetta 2 for running Windows games
- Xcode or the Swift toolchain to build GameWrap from source
- Internet access for the first runtime download (approximately 240 MB)
- Free disk space for the unpacked game, bundled runtime, and optional disk image

## Build and install

From a checkout of this repository:

```sh
scripts/package-app.sh
open ~/Applications/GameWrap.app
```

This builds a release app, signs it ad hoc, and installs it in `~/Applications`. To choose another location:

```sh
scripts/package-app.sh /tmp/gamewrap-preview
```

GameWrap is not notarized. For an app you built yourself, macOS may require using **Open** from Finder's context menu. Avoid removing quarantine attributes from software you do not trust.

## Wrap a game

1. Drop a game onto GameWrap, or choose it with the file picker. Put loose executables and their supporting files in a dedicated game folder first.
2. Check the detected Windows program and app name. Choose a custom icon if you want.
3. Choose **Mac app** or **Mac app + DMG**, select a destination, and build. The runtime downloads automatically if needed.
4. Launch the completed app. First launch prepares a separate Windows environment and can take a minute or more.

Your original game files stay untouched. Each generated app includes its own runtime. Rosetta 2 is still required on the destination Mac.

## Troubleshooting

- **No Windows program found:** choose the folder containing the actual game, rather than a shortcut or installer download page.
- **Archive cannot be unpacked:** encrypted archives are not supported. Extract it yourself and choose the resulting folder.
- **Game does not start:** try another detected executable or the game's documented launch arguments under Advanced settings. Check its `last-run.log`.
- **Build fails:** copy diagnostics from GameWrap. Review them for private information before opening an issue.
- **First launch is slow:** wait for setup to finish before launching again.

Saves, Windows settings, and `last-run.log` live in `~/Library/Application Support/<Game name>/`. The runtime cache lives in `~/Library/Application Support/GameWrap/runtimes/`. Removing a generated app does not delete its saves. Games with the same app name share that support folder, so use distinct names for separate installations.

## Experimental Unity 6 compatibility

Some Unity 6 games need a newer Wine input implementation and a matching Metal graphics backend. OFFRECORD reached its menu and opening scene with a patched Wine 11.8 + DXMT 0.80 configuration. See [tested configuration and repair workflow](docs/compatibility/OFFRECORD.md). This opt-in developer workflow creates a separate app; it is not a universal compatibility guarantee.

## Network and accounts

GameWrap requires no GitHub account or sign-in. Its only application network request is the first-time runtime download from the public Gcenx GitHub release (and normal download redirects). It contains no analytics or telemetry and does not upload your games or diagnostics. GitHub receives ordinary download-request metadata. Once cached, the runtime can be reused offline. Games themselves may have their own network behavior.

GitHub Actions checks run when repository code changes, independently of people running GameWrap. Failure emails go to repository subscribers according to their GitHub notification settings.

## Development and contributions

```sh
swift test --scratch-path "${TMPDIR:-/tmp/}gamewrap-build"
scripts/integration-test.sh  # opt-in: real runtime, signing, and DMG mounting
```

Keep build products outside iCloud-synced folders. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and compatibility reporting, and [docs/TESTING.md](docs/TESTING.md) for recorded acceptance results.

## License and credits

GameWrap's source is [MIT-licensed](LICENSE). The public project contains no game, Wine, or Apple runtime binaries. The runtime is downloaded separately from [Gcenx's build](https://github.com/Gcenx/game-porting-toolkit) and pinned to Game Porting Toolkit 3.0-3 with a SHA-256 check.

Wine, D3DMetal, and games have separate licenses. Generated game bundles are intended for personal use; do not publish them. See [third-party notices](THIRD_PARTY_NOTICES.md).

The native interface follows the [macOS design skill](https://github.com/ceorkm/macos-design-skill). The solarpunk illustration was generated with OpenAI image generation; see [artwork details and prompt](assets/ARTWORK.md). Native pixel accents draw visual inspiration from [Bitlight](https://github.com/berkboz/bitlight).
