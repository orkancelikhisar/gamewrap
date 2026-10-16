import XCTest
@testable import GameWrapCore

final class LauncherTests: XCTestCase {
    func testDXMTLaunchUsesModernWineAndSeparatePrefix() async throws {
        let config = BuildConfig(name: "Unity Game", exe: "Game.exe", destination: try tempDir())
        let manifest = GameManifest(config: config, redists: [], runtimeID: "wine-dxmt-11.8-0.80-v1")
        XCTAssertNil(manifest.env["WINEMSYNC"])
        let home = try tempDir()
        let lines = try await dryRun(try await makeApp(manifest), home: home)
        XCTAssertTrue(lines.contains("WINEPREFIX=\(home.path)/Library/Application Support/Unity Game/DXMT/prefix"))
        XCTAssertTrue(lines.contains("WINEDLLOVERRIDES=winemenubuilder.exe=d;dxgi,d3d11,d3d10core=b"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("EXEC=") && $0.hasSuffix("/bin/wine|Game.exe") })
    }

    func testLauncherHasValidSyntax() async throws {
        let script = try tempDir().appendingPathComponent("launcher")
        try Data(LauncherTemplate.script.utf8).write(to: script)
        try await SystemProcessRunner().run(Tool.zsh, ["-n", script.path])
    }

    func makeApp(_ manifest: GameManifest) async throws -> URL {
        let base = try tempDir()
        let game = base.appendingPathComponent("src")
        try Fixtures.writeExe(game, manifest.exe)
        let wine = base.appendingPathComponent("wine")
        try Fixtures.writeFile(wine, "bin/wine64")
        let icns = try Fixtures.writeFile(base, "AppIcon.icns", "icns")
        return try await BundleAssembler(runner: FakeProcessRunner())
            .assemble(manifest: manifest, gameRoot: game, wine: wine, icns: icns, in: base)
    }

    func dryRun(_ app: URL, home: URL) async throws -> [String] {
        let launcher = app.appendingPathComponent("Contents/MacOS/launcher")
        let result = try await SystemProcessRunner().run(Tool.zsh, [launcher.path], cwd: nil, env: ["GAMEWRAP_DRY_RUN": "1", "HOME": home.path])
        return result.output.split(separator: "\n").map(String.init)
    }

    // Review focus 1: quotes, spaces and arguments survive the launcher.
    func testDryRunWithAwkwardNamesAndArguments() async throws {
        let manifest = GameManifest(name: "Baldur's Gate 3", exe: "bin/Game Shipping.exe",
                                    args: ["-dx11", "--name=O'Brien Two"], redists: [],
                                    env: ["WINEMSYNC": "1", "ROSETTA_ADVERTISE_AVX": "1"], showFPS: true, runtime: "rt")
        let home = try tempDir()
        let lines = try await dryRun(try await makeApp(manifest), home: home)

        XCTAssertTrue(lines.contains("WINEPREFIX=\(home.path)/Library/Application Support/Baldur's Gate 3/prefix"), "\(lines)")
        XCTAssertTrue(lines.contains("WINEDLLOVERRIDES=winemenubuilder.exe=d"))
        XCTAssertTrue(lines.contains("WINEDEBUG=-all"))
        XCTAssertTrue(lines.contains("WINEMSYNC=1"))
        XCTAssertTrue(lines.contains("ROSETTA_ADVERTISE_AVX=1"))
        XCTAssertTrue(lines.contains("MTL_HUD_ENABLED=1"))
        XCTAssertTrue(lines.contains("REDISTS="))
        let cwd = try XCTUnwrap(lines.first { $0.hasPrefix("CWD=") })
        XCTAssertTrue(cwd.hasSuffix("/Contents/Resources/game/bin"), cwd)
        let exec = try XCTUnwrap(lines.first { $0.hasPrefix("EXEC=") })
        XCTAssertTrue(exec.hasSuffix("/Contents/Resources/wine/bin/wine64|Game Shipping.exe|-dx11|--name=O'Brien Two"), exec)
        // A dry run must not create anything in the user's Library.
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library").path))
    }

    func testDryRunWithoutFPSAndWithRedists() async throws {
        let manifest = GameManifest(name: "Plain", exe: "game.exe", redists: ["r/vc_redist.x64.exe"],
                                    env: ["WINEMSYNC": "1"], showFPS: false, runtime: "rt")
        let lines = try await dryRun(try await makeApp(manifest), home: try tempDir())
        XCTAssertFalse(lines.contains("MTL_HUD_ENABLED=1"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("ROSETTA_ADVERTISE_AVX") })
        XCTAssertTrue(lines.contains("REDISTS=r/vc_redist.x64.exe"))
        let cwd = try XCTUnwrap(lines.first { $0.hasPrefix("CWD=") })
        XCTAssertTrue(cwd.hasSuffix("/Contents/Resources/game/."), cwd)
    }
}
