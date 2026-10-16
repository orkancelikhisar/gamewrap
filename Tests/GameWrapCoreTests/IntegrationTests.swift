import XCTest
@testable import GameWrapCore

/// End-to-end build with real tools and the real runtime (downloads 240 MB on first run).
/// Run with: scripts/integration-test.sh
final class IntegrationTests: XCTestCase {
    func testRealBuildProducesSignedAppAndMountableDMG() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GAMEWRAP_INTEGRATION"] == "1", "set GAMEWRAP_INTEGRATION=1")
        let base = try tempDir()
        let game = base.appendingPathComponent("Stub Game")
        let png = ImageFixtures.png(width: 128)
        try Fixtures.writeExe(game, "Stub Game.exe", resources: [
            PEFile.rtIcon: [1: png], PEFile.rtGroupIcon: [1: ImageFixtures.groupIcon([(128, 1, png.count)])],
        ])
        let destination = base.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let runner = SystemProcessRunner()
        let gw = GameWrap()
        let info = try await gw.inspect(game)
        defer { gw.discard(info) }

        var result: BuildResult?
        for try await event in gw.build(info, BuildConfig(name: "Stub Game", exe: "Stub Game.exe", output: .appAndDMG, destination: destination)) {
            if case .finished(let r) = event { result = r }
        }
        let built = try XCTUnwrap(result)
        try await runner.run(Tool.codesign, ["--verify", "--deep", "--strict", built.app.path])

        // The bundled Wine must work from inside the app (relocatable runtime).
        let version = try await runner.run(built.app.appendingPathComponent("Contents/Resources/wine/bin/wine64").path, ["--version"])
        XCTAssertTrue(version.output.lowercased().contains("wine"), version.output)

        // The launcher dry run resolves the bundled paths.
        let dry = try await runner.run(Tool.zsh, [built.app.appendingPathComponent("Contents/MacOS/launcher").path],
                                       cwd: nil, env: ["GAMEWRAP_DRY_RUN": "1", "HOME": base.path])
        XCTAssertTrue(dry.output.contains("|Stub Game.exe"), dry.output)

        // The dmg mounts and contains the app plus the Applications shortcut.
        let mount = base.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try await runner.run(Tool.hdiutil, ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, try XCTUnwrap(built.dmg).path])
        let contents = try FileManager.default.contentsOfDirectory(atPath: mount.path)
        try await runner.run(Tool.hdiutil, ["detach", mount.path])
        XCTAssertEqual(Set(contents.filter { !$0.hasPrefix(".") }), ["Stub Game.app", "Applications"])
    }
}
