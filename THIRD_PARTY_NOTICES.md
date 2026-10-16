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
