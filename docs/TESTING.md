# Testing and verification

Last verified: 2026-10-16, Apple silicon, macOS 26.6.2. GameWrap is an early preview; successful packaging does not establish game compatibility.

## Routine checks

```sh
swift test --scratch-path "${TMPDIR:-/tmp/}gamewrap-build"
zsh -n scripts/package-app.sh scripts/integration-test.sh
scripts/package-app.sh /tmp/gamewrap-preview
codesign --verify --deep --strict /tmp/gamewrap-preview/GameWrap.app
```

The latest full suite passed: **73 passed, two opt-in tests skipped, zero failures**. It covers importing, PE detection, icons, argument quoting, both launcher profiles, isolated save paths, runtime checksums, incomplete installations, cache reuse, build cancellation, packaging, and app-model regressions.

[Hosted macOS checks](https://github.com/orkancelikhisar/gamewrap/actions) run the normal suite, shell syntax checks, and release packaging/signature verification. They do not run games or download the runtime fixtures.

## Opt-in runtime acceptance

### Standard engine

```sh
scripts/integration-test.sh
```

Previously passed with the real cached runtime and macOS tools: app assembly/signing, bundled Wine execution, launcher dry run, DMG creation, verification, mounting, and contents inspection. First-time runtime download is approximately 240 MB.

### Unity 6 / DXMT engine

Prepare a directory containing the pinned archives listed in [OFFRECORD compatibility](compatibility/OFFRECORD.md), named `wine.tar.xz`, `dxmt.tar.gz`, and `dependencies.tar.xz`. Provide a dedicated game folder containing OFFRECORD's files:

```sh
GAMEWRAP_DXMT_ARCHIVES=/path/to/archives \
GAMEWRAP_DXMT_GAME=/path/to/OFFRECORD \
swift test --scratch-path "${TMPDIR:-/tmp/}gamewrap-build" \
  --filter DXMTRuntimeTests.testRealDXMTInstallerAndGameBuild
```

This test installs the real engine into GameWrap's runtime cache and creates `/tmp/gamewrap-integrated-dxmt/OFFRECORD Integrated DXMT.app`. It requires Rosetta 2 and several GB of free disk space. Use a fresh output location by moving an existing acceptance app before repeating the test.

The real test passed independently of the normal suite. It verified composition of the pinned archives, app assembly, signing, manifest settings, and bundled license. First launch completed in the isolated DXMT prefix; its installed graphics DLLs matched the bundled copies. The Unity log reached the opening game scene. Interactive inspection of the final integrated UI was interrupted by the Mac locking; the engine picker itself was observed.

## Manual acceptance recorded

- Opening screen fits without scrolling; native system appearance, keyboard selection with Command-O, and animated pixel controller are present. Motion respects Reduce Motion and pauses for inactive scenes.
- The solarpunk illustration is used in the README only, not bundled in the app.
- Choosing an empty folder produces an error with recovery and diagnostics.
- Hyperballin imported, built, completed first-launch setup, and rendered its menu with Standard. Relaunch reused its prefix. A save file was observed; restoration of game progress was not verified.
- OFFRECORD rendered its menu, accepted Start Game, and reached its opening scene with the patched Wine/DXMT combination. See [compatibility details](compatibility/OFFRECORD.md).

## Remaining release validation

Full-game play, performance, audio, controllers, and save/load restoration remain unverified. Test on the oldest supported macOS version, a second Mac, and a clean runtime installation. Signing remains ad hoc; Developer ID signing and notarization are not configured.
