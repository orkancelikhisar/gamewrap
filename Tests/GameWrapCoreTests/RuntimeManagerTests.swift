import XCTest
@testable import GameWrapCore

final class RuntimeManagerTests: XCTestCase {
    /// A tar.xz shaped like the Gcenx release: Game Porting Toolkit.app/Contents/Resources/wine/...
    func makeArchive(includeD3DMetal: Bool = true) async throws -> URL {
        let staging = try tempDir()
        let wine = "Game Porting Toolkit.app/Contents/Resources/wine"
        try Fixtures.writeFile(staging, "\(wine)/bin/wine64", "#!/bin/sh\n")
        if includeD3DMetal { try Fixtures.writeFile(staging, "\(wine)/lib/external/D3DMetal.framework/D3DMetal") }
        let archive = try tempDir().appendingPathComponent("gptk.tar.xz")
        try await SystemProcessRunner().run(Tool.bsdtar, ["-cJf", archive.path, "-C", staging.path, "Game Porting Toolkit.app"])
        return archive
    }

    func manager(for archive: URL, sha: String? = nil, root: URL) throws -> RuntimeManager {
        let spec = RuntimeSpec(id: "test-rt", url: archive, sha256: try sha ?? RuntimeManager.sha256(of: archive), downloadSize: 1)
        return RuntimeManager(spec: spec, root: root, runner: SystemProcessRunner())
    }

    func testInstallsFromArchiveAndReportsInstalled() async throws {
        let root = try tempDir()
        let rt = try manager(for: try await makeArchive(), root: root)
        XCTAssertFalse(rt.isInstalled())
        let progress = ProgressRecorder()
        let wine = try await rt.ensureInstalled { progress.record($0) }
        XCTAssertEqual(wine, rt.wineURL)
        XCTAssertTrue(rt.isInstalled())
        XCTAssertTrue(FileManager.default.fileExists(atPath: wine.appendingPathComponent("bin/wine64").path))
        XCTAssertEqual(progress.values.last, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".partial-test-rt").path))
    }

    func testSecondCallDoesNotDownloadAgain() async throws {
        let archive = try await makeArchive()
        let rt = try manager(for: archive, root: try tempDir())
        _ = try await rt.ensureInstalled { _ in }
        try FileManager.default.removeItem(at: archive)
        _ = try await rt.ensureInstalled { _ in }
        XCTAssertTrue(rt.isInstalled())
    }

    func testChecksumMismatchInstallsNothing() async throws {
        let root = try tempDir()
        let rt = try manager(for: try await makeArchive(), sha: String(repeating: "0", count: 64), root: root)
        do {
            _ = try await rt.ensureInstalled { _ in }
            XCTFail("expected checksum mismatch")
        } catch let error as GameWrapError {
            XCTAssertEqual(error, .runtimeChecksumMismatch)
        }
        XCTAssertFalse(rt.isInstalled())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testArchiveWithoutD3DMetalIsRejected() async throws {
        let rt = try manager(for: try await makeArchive(includeD3DMetal: false), root: try tempDir())
        do {
            _ = try await rt.ensureInstalled { _ in }
            XCTFail("expected runtimeDownloadFailed")
        } catch GameWrapError.runtimeDownloadFailed {
        }
        XCTAssertFalse(rt.isInstalled())
    }

    // Review focus 4: a leftover partial download from an interrupted run is cleaned up.
    func testLeftoverPartialDownloadIsReplaced() async throws {
        let root = try tempDir()
        try Fixtures.writeFile(root, ".partial-test-rt/runtime.tar.xz", "half a download")
        try Fixtures.writeFile(root, "test-rt/wine/bin/wine64")   // incomplete install: no D3DMetal
        let rt = try manager(for: try await makeArchive(), root: root)
        XCTAssertFalse(rt.isInstalled())
        _ = try await rt.ensureInstalled { _ in }
        XCTAssertTrue(rt.isInstalled())
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".partial-test-rt").path))
    }

    // Final review fix: a download from the UI and a build must not fight over one install.
    func testConcurrentInstallsShareOneDownload() async throws {
        let archive = try await makeArchive()
        let root = try tempDir()
        let managers = try (0..<8).map { _ in try manager(for: archive, root: root) }
        try await withThrowingTaskGroup(of: URL.self) { group in
            for m in managers { group.addTask { try await m.ensureInstalled { _ in } } }
            for try await _ in group {}
        }
        XCTAssertTrue(managers[0].isInstalled())
    }

    func testPinnedSpecMatchesTheSpec() {
        XCTAssertEqual(RuntimeSpec.gptk303.id, "gptk-3.0-3")
        XCTAssertEqual(RuntimeSpec.gptk303.sha256, "d377683937340f914823dbb2e1252b329cbf834ff58907d0293db8cebf0e392e")
        XCTAssertEqual(RuntimeSpec.gptk303.url.absoluteString,
                       "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz")
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double] = []
    func record(_ value: Double) { lock.withLock { recorded.append(value) } }
    var values: [Double] { lock.withLock { recorded } }
}
