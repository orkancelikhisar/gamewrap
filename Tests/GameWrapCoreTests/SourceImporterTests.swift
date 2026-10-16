import XCTest
@testable import GameWrapCore

final class SourceImporterTests: XCTestCase {
    let importer = SourceImporter(runner: SystemProcessRunner())

    func testFolderIsUsedInPlace() async throws {
        let game = try tempDir().appendingPathComponent("My Game")
        try Fixtures.writeExe(game, "game.exe")
        let work = try tempDir()
        let result = try await importer.importSource(game, workDir: work)
        XCTAssertEqual(result.gameRoot, game)
        XCTAssertEqual(result.suggestedName, "My Game")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.path), [])
    }

    func testExeUsesItsFolder() async throws {
        let game = try tempDir()
        let exe = try Fixtures.writeExe(game, "Cool Game.exe")
        let result = try await importer.importSource(exe, workDir: try tempDir())
        XCTAssertEqual(result.gameRoot.resolvingSymlinksInPath().path, game.resolvingSymlinksInPath().path)
        XCTAssertEqual(result.suggestedName, "Cool Game")
    }

    // Review focus 3: wrapper folders and __MACOSX junk are skipped.
    func testArchiveDescendsIntoSingleWrapperFolders() async throws {
        let staging = try tempDir()
        try Fixtures.writeExe(staging, "Game v1/Windows/game.exe")
        try Fixtures.writeFile(staging, "Game v1/Windows/data.pak")
        try Fixtures.writeFile(staging, "__MACOSX/._junk")
        let archive = try tempDir().appendingPathComponent("Game v1.zip")
        try await SystemProcessRunner().run(Tool.bsdtar, ["-a", "-cf", archive.path, "-C", staging.path, "Game v1", "__MACOSX"])

        let work = try tempDir()
        let result = try await importer.importSource(archive, workDir: work)
        XCTAssertEqual(result.gameRoot.lastPathComponent, "Windows")
        XCTAssertTrue(result.gameRoot.resolvingSymlinksInPath().path.hasPrefix(work.resolvingSymlinksInPath().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.gameRoot.appendingPathComponent("game.exe").path))
        XCTAssertEqual(result.suggestedName, "Game v1")
    }

    func testArchiveWithSeveralTopLevelItemsStaysAtTop() async throws {
        let staging = try tempDir()
        try Fixtures.writeExe(staging, "game.exe")
        try Fixtures.writeFile(staging, "data/a.pak")
        let archive = try tempDir().appendingPathComponent("g.zip")
        try await SystemProcessRunner().run(Tool.bsdtar, ["-a", "-cf", archive.path, "-C", staging.path, "game.exe", "data"])
        let result = try await importer.importSource(archive, workDir: try tempDir())
        XCTAssertEqual(result.gameRoot.lastPathComponent, "source")
    }

    func testCorruptArchiveThrowsImportFailed() async throws {
        let bad = try Fixtures.writeFile(try tempDir(), "bad.zip", "not a zip at all")
        do {
            _ = try await importer.importSource(bad, workDir: try tempDir())
            XCTFail("expected importFailed")
        } catch GameWrapError.importFailed {
        }
    }

    func testUnsupportedAndMissingSources() async throws {
        let txt = try Fixtures.writeFile(try tempDir(), "readme.txt")
        let missing = URL(fileURLWithPath: "/nonexistent/game.exe")
        for source in [txt, missing] {
            do {
                _ = try await importer.importSource(source, workDir: try tempDir())
                XCTFail("expected unsupportedSource for \(source)")
            } catch let error as GameWrapError {
                XCTAssertEqual(error, .unsupportedSource(source))
            }
        }
    }
}
