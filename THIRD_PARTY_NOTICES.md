# Third-party software and design references

GameWrap's source is MIT-licensed; see [LICENSE](LICENSE).

## Runtime

GameWrap downloads a pinned build from [Gcenx/game-porting-toolkit](https://github.com/Gcenx/game-porting-toolkit). The repository and packaged GameWrap utility do not contain that runtime or any game files.

The downloaded runtime includes Wine, D3DMetal, and other components under their respective licenses. GameWrap's MIT license does not relicense them. See the upstream source and the notices supplied with the runtime, and [Apple's Game Porting Toolkit information](https://developer.apple.com/games/game-porting-toolkit/). Generated game apps contain the runtime and remain subject to its terms and the game's own license. This project does not grant permission to redistribute games or runtime components.

The runtime is pinned to `gptk-3.0-3`; it is not automatically updated to newer toolkit releases.

## Visual reference

The single-screen interface uses original native SwiftUI pixel artwork inspired by the ordered-dither treatment in [Bitlight](https://github.com/berkboz/bitlight) by Berk Boz and contributors. No Bitlight source code, fonts, images, or JavaScript runtime are bundled.

System fonts and SF Symbols are supplied by macOS.

The interface was refined using the [macOS design skill](https://github.com/ceorkm/macos-design-skill). The solarpunk illustration is AI-generated for this project using OpenAI image generation; see [artwork notes](assets/ARTWORK.md).

## Optional Unity 6 / DXMT engine

This opt-in engine downloads Wine Staging 11.8_mm1 from [zzzz465/homebrew-wine-dxmt](https://github.com/zzzz465/homebrew-wine-dxmt/releases/tag/v11.8_mm1), [DXMT 0.80](https://github.com/3Shain/dxmt/tree/v0.80), and dependency libraries from [Gcenx Wine 11.18](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18). All three archives are pinned by SHA-256. Wine and DXMT are LGPL-2.1-or-later; DXMT copyright © 2023–2026 Feifan He for CodeWeavers. The LGPL text and upstream source links are included in the assembled runtime. Dependencies retain their upstream licenses. No component binaries are shipped with the GameWrap utility or source repository.
