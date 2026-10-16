# OFFRECORD compatibility investigation

Tested 2026-10-16 on an Apple M4 Mac, with Unity 6000.0.70f1.

- Current GameWrap runtime (`gptk-3.0-3`): aborts at unimplemented `USER32.dll.IsMouseInPointerEnabled`.
- Official macOS Wine development package 11.18, downloaded from Gcenx/macOS_Wine_builds: initializes the Unity input module successfully, then fails Direct3D 11 device creation with `80004005`.
- Wine 11.18 with its Vulkan renderer selected in the isolated prefix: same Direct3D device creation failure.
- Wine 11.18 with Unity `-force-vulkan`: Unity reports that Vulkan was not built into this game and shaders are unavailable.

All newer-runtime tests used a separate disposable prefix. The original game app, current runtime cache, and original save environment were not modified. Test processes were stopped afterward.

Result: not compatible with either tested configuration. Do not switch GameWrap's default runtime based on these tests. A newer runtime with a compatible, tested Direct3D translation stack is needed; graphics and input must both work before recommending it.

Upstream package: https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18

## Working startup configuration

Follow-up testing found a working combination:

- Wine Staging 11.8_mm1 from [zzzz465/homebrew-wine-dxmt](https://github.com/zzzz465/homebrew-wine-dxmt/releases/tag/v11.8_mm1), which exports `macdrv_functions`.
- Official [DXMT v0.80 builtin release](https://github.com/3Shain/dxmt/releases/tag/v0.80).
- Missing runtime dylibs supplied from [Gcenx Wine Devel 11.18](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18), bundled locally and found through `DYLD_FALLBACK_LIBRARY_PATH`.
- Builtin overrides for `dxgi,d3d11,d3d10core`; no `WINEMSYNC` override inherited from GPTK.

Verified visually: title menu renders, Start Game responds, opening Day1_01 scene renders. This is a startup and input check, not full-game, controller, audio, performance, or save/load acceptance.

The newer stock Wine 11.18 and stable 11.0_1 Mac drivers do not export the interface required by the tested DXMT release. Selecting a Wine version solely by its version number is insufficient.

### Reproduce the repair

Use `python3 scripts/repair-dxmt-app.py --help`. Supply an existing GameWrap app, the unpacked patched Wine's `Contents/Resources/wine` directory, the unpacked DXMT `v0.80` directory, a new destination app, and the Gcenx runtime's `lib` directory through `--dependency-lib`.

The script verifies the driver interface, creates a separate app, copies runtime dependencies into that app, and uses a separate save environment based on the new app name. It never modifies the input app. This is an experimental opt-in developer workflow; the default GameWrap runtime remains unchanged. Only the repair script is in this repository, with no game or runtime binaries.

Downloaded archive SHA-256 values for the tested inputs:

```
236e517c12b8adf2092607742c4337632f7b03ffc06e4341bc5fc0a8f0160a9f  wine-staging-11.8_mm1-osx64.tar.xz
8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d  dxmt-v0.80-builtin.tar.gz
aa0ea4c82e636ae7bca2076387cb0a5affa26509ad13f119ecd0d62bd7ba6f82  wine-devel-11.18-osx64.tar.xz
```

These hashes record the inputs tested here, rather than an independent upstream signature verification. Runtime and graphics components retain their upstream licenses and source obligations; the utility's MIT license does not relicense them.
