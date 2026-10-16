# Verification record

Verified locally on 2026-10-16 using an Apple silicon Mac running macOS 26.6.2. This is an early-preview acceptance record, not a claim that every Windows game or supported macOS version works.

## Automated checks

- Core suite: 68 tests, 67 passed and the opt-in integration test skipped, zero failures.
- App model regressions: 2 passed. Covers resetting per-game settings/diagnostics and preserving the current icon when an unreadable image is selected. Both tests were observed failing before their fixes.
- Opt-in integration: 1 passed with real tools. Built and signed an app with the cached runtime, executed bundled Wine, checked launcher dry-run paths, and created/verified/mounted/inspected a DMG.
- Release packaging: app built and ad-hoc signature verified. The package includes its own icon, MIT license, and third-party notices.
- A macOS GitHub Actions workflow is supplied; it has not yet run on GitHub.

## Native UI acceptance

- Packaged app opens and reports the installed runtime.
- Choosing an empty folder displays a useful error; Back returns to game selection.
- The Hyperballin RAR imports successfully, detects `project_garden/Binaries/Win64/project_garden-Win64-Shipping.exe`, and extracts its blue ball icon.
- Switching App to App + DMG updates the default destination. Selecting a custom destination works.
- Building Hyperballin through the UI produces an app and DMG successfully.
- The redesign keeps selection and setup in one window. Settings, progress, results, and error recovery occupy the same right-hand panel. Advanced settings are collapsible; the icon picker is a labeled button.

## Real-game acceptance

Hyperballin Alpha rc0209 was built from its local RAR through GameWrap's UI using the pinned GPTK 3.0-3 runtime.

- First launch completed prefix setup and created `.gamewrap-ready`.
- Startup graphics and the animated main menu rendered visibly.
- Quit/relaunch reused the existing setup marker; D3DMetal output was recorded in the game log.
- D3DMetal emitted unsupported-API warnings. These did not prevent the observed menu from rendering.
- Extended gameplay, performance, controller behavior, save persistence, and a second game have not been validated.

## Before a stable public release

Test on the oldest claimed macOS version and a second Mac, validate a second game, and perform longer gameplay checks. A downloaded-runtime installation on a clean machine also needs manual acceptance. Signing is ad hoc; Developer ID signing/notarization is not configured.

The repository has no configured Git remote at the time of this record. Publishing and hosted CI remain outstanding.

### Opening-screen refinement

Replaced the landscape with a compact native animated pixel controller, increased the minimum window height to 620 points, and verified the opening screen fits with its footer and no scrollbar. Motion pauses when the scene is inactive and respects Reduce Motion. The revised release build and code-signature verification passed.

### Native interface and public release preparation

Replaced the numbered two-column layout with a centered drop area and a single configuration view. Removed promotional headings, adopted system colors and typography, and added Command-O for choosing a game. The generated solarpunk illustration is a SwiftPM resource copied into the signed application bundle. Verified its rendering in the packaged app, the opening screen without scrolling, and the Command-O file picker. The complete unit suite passed again (69 passed, one opt-in integration test skipped); release packaging and strict code-signature checks passed. The earlier real-game acceptance limits still apply.
