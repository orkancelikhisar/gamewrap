# OFFRECORD compatibility

Tested 2026-10-16 on Apple M4 with Unity 6000.0.70f1.

## Use in GameWrap

Choose **Unity 6 / DXMT (experimental)** under Compatibility engine before building OFFRECORD. GameWrap downloads and verifies the components below and bundles the assembled runtime in the Mac app. Keep Standard for games that already work or need Direct3D 12.

DXMT saves and Windows settings use `~/Library/Application Support/<Game name>/DXMT/prefix`, separate from the Standard engine. Switching engines does not migrate saves.

Verified visually with the tested combination: menu rendering, Start Game input, and the opening Day1_01 scene. The integrated builder also passed real-archive installation, assembly, signing, and first-launch setup; its Unity log reached the opening scene. Full gameplay, audio, controllers, performance, and save/load restoration remain unverified.

## Pinned components

| Component | Release | Purpose |
| --- | --- | --- |
| Patched Wine Staging | [11.8_mm1](https://github.com/zzzz465/homebrew-wine-dxmt/releases/tag/v11.8_mm1) | Unity input support and exported `macdrv_functions` interface |
| DXMT builtin | [0.80](https://github.com/3Shain/dxmt/releases/tag/v0.80) | Direct3D 10/11 to Metal translation |
| Gcenx Wine Devel | [11.18](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18) | Missing runtime library dependencies |

The installer uses builtin overrides for `dxgi,d3d11,d3d10core` and bundles dependencies locally. It does not inherit GPTK's `WINEMSYNC` setting.

SHA-256 hashes checked before extraction:

```
236e517c12b8adf2092607742c4337632f7b03ffc06e4341bc5fc0a8f0160a9f  wine-staging-11.8_mm1-osx64.tar.xz
8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d  dxmt-v0.80-builtin.tar.gz
aa0ea4c82e636ae7bca2076387cb0a5affa26509ad13f119ecd0d62bd7ba6f82  wine-devel-11.18-osx64.tar.xz
```

These record the tested inputs, not an independent upstream signature verification. Runtime components retain their upstream licenses; see [third-party notices](../../THIRD_PARTY_NOTICES.md). No game or runtime binaries are stored in this repository.

## Why the Standard engine fails

GPTK 3.0-3 aborts when Unity calls the unimplemented `USER32.dll.IsMouseInPointerEnabled` function. Stock Wine 11.18 gets past input initialization but fails Direct3D device creation, including with Wine's Vulkan renderer. Unity's `-force-vulkan` option also fails because this game was not built with Vulkan support.

Adding DXMT alone to the stock Wine builds was insufficient: their Mac drivers did not export the interface needed by DXMT. The patched Wine build supplies that interface. Wine version number alone does not establish compatibility.

## Developer acceptance

See [testing instructions](../TESTING.md#unity-6--dxmt-engine) for reproducing the integrated build test. The earlier manual repair script has been superseded by the app's compatibility-engine option.
