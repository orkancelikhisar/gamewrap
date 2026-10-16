# Contributing to GameWrap

GameWrap is a native SwiftUI app for Apple silicon Macs. Small fixes, accessibility improvements, documentation, and reproducible compatibility reports are welcome.

## Develop

Use an Apple silicon Mac, macOS 14 or later, and Xcode or the Swift toolchain. There are no third-party Swift dependencies.

```sh
swift test --scratch-path "${TMPDIR:-/tmp/}gamewrap-build"
scripts/package-app.sh /tmp/gamewrap-preview
open /tmp/gamewrap-preview/GameWrap.app
```

Keep build products outside iCloud-synced folders: File Provider attributes can interfere with code signing. The normal suite uses small generated fixtures, not commercial game files. It skips the runtime integration test.

```sh
scripts/integration-test.sh
```

The opt-in integration test uses real signing and disk-image tools and downloads approximately 240 MB on its first run. Rosetta 2 is required to execute the bundled Wine. Hosted CI runs the normal suite and packaging check; it does not establish game compatibility.

## Make a change

1. Open an issue for substantial behavior changes so scope can be discussed.
2. Keep changes focused. Preserve source files and keep build work in temporary folders.
3. Add regression tests for behavioral fixes. Run the full test suite and package the app.
4. For UI changes, check keyboard access, readable contrast, and the smallest supported window. Include screenshots with personal paths hidden.
5. Submit a pull request describing the problem, resulting behavior, and verification.

`GameWrapCore` owns importing, detection, runtime installation, bundle assembly, and packaging. `GameWrapApp` owns the interface. Do not commit game files, downloaded runtimes, Wine prefixes, credentials, or private logs.

## Compatibility reports

Include your Mac chip, macOS version, GameWrap revision, game version, chosen executable, launch arguments, and observed behavior. Distinguish “builds successfully” from “launches and renders” and “playable.” Review logs for usernames, paths, and other personal information before sharing them. Do not attach copyrighted game files.

Be respectful and constructive. Contributions are provided under the project's MIT license.
