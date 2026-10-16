import XCTest
@testable import GameWrapCore

final class BundleAssemblerTests: XCTestCase {
    func testSlugAndFileName() {
        XCTAssertEqual(BundleAssembler.slug("Hyperballin"), "hyperballin")
        XCTAssertEqual(BundleAssembler.slug("Baldur's Gate 3"), "baldur-s-gate-3")
        XCTAssertEqual(BundleAssembler.slug("Café Racer"), "caf-racer")
        XCTAssertEqual(BundleAssembler.slug("!!!"), "game")
        XCTAssertEqual(BundleAssembler.bundleFileName("AC/DC: Live"), "AC-DC- Live")
        XCTAssertEqual(BundleAssembler.bundleFileName("  "), "Game")
    }

    func testInfoPlist() {
        let plist = BundleAssembler.infoPlist(for: GameManifest(name: "Baldur's Gate 3", exe: "g.exe", runtime: "rt"))
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "local.gamewrap.baldur-s-gate-3")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "launcher")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Baldur's Gate 3")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "14.0")
        XCTAssertEqual(plist["LSApplicationCategoryType"] as? String, "public.app-category.games")
    }

    func testAssemblesTheSpecLayout() async throws {
        let base = try tempDir()
        let game = base.appendingPathComponent("game-src")
        try Fixtures.writeExe(game, "bin/g.exe")
        let wine = base.appendingPathComponent("wine")
        try Fixtures.writeFile(wine, "bin/wine64")
        let icns = try Fixtures.writeFile(base, "AppIcon.icns", "icns")
        let out = base.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let manifest = GameManifest(name: "Baldur's Gate 3", exe: "bin/g.exe", runtime: "rt")
        let runner = FakeProcessRunner()

        let app = try await BundleAssembler(runner: runner).assemble(manifest: manifest, gameRoot: game, wine: wine, icns: icns, in: out)

        XCTAssertEqual(app.lastPathComponent, "Baldur's Gate 3.app")
        let contents = app.appendingPathComponent("Contents")
        let fm = FileManager.default
        for path in ["Info.plist", "MacOS/launcher", "Resources/AppIcon.icns", "Resources/gamewrap.json",
                     "Resources/wine/bin/wine64", "Resources/wine/LICENSE-NOTICE.txt", "Resources/game/bin/g.exe"] {
            XCTAssertTrue(fm.fileExists(atPath: contents.appendingPathComponent(path).path), path)
        }
        XCTAssertTrue(fm.isExecutableFile(atPath: contents.appendingPathComponent("MacOS/launcher").path))
        let decoded = try JSONDecoder().decode(GameManifest.self, from: Data(contentsOf: contents.appendingPathComponent("Resources/gamewrap.json")))
        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(runner.calls.map(\.tool), [Tool.ditto, Tool.ditto])
    }
}
