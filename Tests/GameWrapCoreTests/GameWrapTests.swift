import XCTest
@testable import GameWrapCore

final class GameWrapTests: XCTestCase {
    var base: URL!
    var gameFolder: URL!
    var destination: URL!

    override func setUp() async throws {
        base = try tempDir()
        gameFolder = base.appendingPathComponent("Hollow Thing")
        let png = ImageFixtures.png(width: 64)
        try Fixtures.writeExe(gameFolder, "Hollow Thing.exe", padTo: 10_000, resources: [
            PEFile.rtIcon: [1: png], PEFile.rtGroupIcon: [1: ImageFixtures.groupIcon([(64, 1, png.count)])],
        ])
        try Fixtures.writeExe(gameFolder, "_CommonRedist/vcredist/VC_redist.x64.exe")
        try Fixtures.writeFile(gameFolder, "Data/level1.pak", "level")
        destination = base.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    func makeWrap(runner: FakeProcessRunner = FakeProcessRunner(), space: Int64 = .max) throws -> GameWrap {
        GameWrap(runner: runner, runtime: try FakeRuntime.make(in: base), availableSpace: { _ in space })
    }

    func collect(_ stream: AsyncThrowingStream<BuildEvent, Error>) async throws -> [BuildEvent] {
        var events: [BuildEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    func result(_ events: [BuildEvent]) -> (app: String, dmg: String?)? {
        guard case .finished(let r) = events.last else { return nil }
        return (r.app.path, r.dmg?.path)
    }

    func buildFolders(_ info: SourceInfo) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: info.imported.workDir.path)) ?? []).filter { $0.hasPrefix("build-") }
    }

    func snapshot(_ dir: URL) -> [String: Date] {
        var result: [String: Date] = [:]
        for file in FileScan.files(in: dir, where: { _ in true }) {
            result[file.relativePath] = try? file.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        return result
    }

    func testInspectFolder() async throws {
        let info = try await makeWrap().inspect(gameFolder)
        XCTAssertEqual(info.imported.gameRoot, gameFolder)
        XCTAssertEqual(info.imported.suggestedName, "Hollow Thing")
        XCTAssertEqual(info.candidates.first?.relativePath, "Hollow Thing.exe")
        XCTAssertEqual(info.redists, ["_CommonRedist/vcredist/VC_redist.x64.exe"])
        XCTAssertNotNil(info.iconPNG)
        XCTAssertGreaterThan(info.sizeBytes, 10_000)
    }

    func testInspectWithoutExeThrowsAndCleansUp() async throws {
        let empty = base.appendingPathComponent("empty")
        try Fixtures.writeFile(empty, "readme.txt")
        func workDirs() throws -> Set<String> {
            Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
                .filter { $0.hasPrefix("gamewrap-") })
        }
        let before = try workDirs()
        do {
            _ = try await makeWrap().inspect(empty)
            XCTFail("expected noExeFound")
        } catch let error as GameWrapError {
            XCTAssertEqual(error, .noExeFound)
        }
        XCTAssertEqual(try workDirs(), before, "a failed inspect must delete its work folder")
    }

    func testBuildAppHappyPath() async throws {
        let runner = FakeProcessRunner()
        let gw = try makeWrap(runner: runner)
        let info = try await gw.inspect(gameFolder)
        let before = snapshot(gameFolder)
        let config = BuildConfig(name: "Hollow Thing", exe: "Hollow Thing.exe", args: ["-windowed"], destination: destination)

        let events = try await collect(gw.build(info, config))

        let started = events.compactMap { if case .step(let s, .started) = $0 { return s } else { return nil } }
        XCTAssertEqual(started, [.preflight, .runtime, .importSource, .icon, .assemble, .sign, .deliver])
        let app = destination.appendingPathComponent("Hollow Thing.app")
        XCTAssertEqual(result(events)?.app, app.path)
        XCTAssertNil(result(events)?.dmg)
        let manifest = try JSONDecoder().decode(GameManifest.self, from: Data(contentsOf: app.appendingPathComponent("Contents/Resources/gamewrap.json")))
        XCTAssertEqual(manifest.exe, "Hollow Thing.exe")
        XCTAssertEqual(manifest.args, ["-windowed"])
        XCTAssertEqual(manifest.redists, ["_CommonRedist/vcredist/VC_redist.x64.exe"])
        XCTAssertEqual(manifest.runtime, "fake-rt")
        XCTAssertTrue(events.contains { if case .log(let line) = $0 { return line.hasPrefix("$ codesign") } else { return false } })
        XCTAssertEqual(buildFolders(info), [], "the build's temporary folder must be deleted")
        XCTAssertEqual(snapshot(gameFolder), before, "the source must never be modified")
    }

    func testBuildAppAndDMG() async throws {
        let gw = try makeWrap()
        let info = try await gw.inspect(gameFolder)
        let config = BuildConfig(name: "Hollow Thing", exe: "Hollow Thing.exe", output: .appAndDMG, destination: destination)
        let events = try await collect(gw.build(info, config))
        XCTAssertTrue(events.contains(.step(.package, .started)))
        let dmg = destination.appendingPathComponent("Hollow Thing.dmg")
        XCTAssertEqual(result(events)?.app, destination.appendingPathComponent("Hollow Thing.app").path)
        XCTAssertEqual(result(events)?.dmg, dmg.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dmg.path))
    }

    func testNotEnoughSpaceFailsBeforeAnyWork() async throws {
        let runner = FakeProcessRunner()
        let gw = try makeWrap(runner: runner, space: 0)
        let info = try await gw.inspect(gameFolder)
        do {
            _ = try await collect(gw.build(info, BuildConfig(name: "G", exe: "Hollow Thing.exe", destination: destination)))
            XCTFail("expected insufficientSpace")
        } catch GameWrapError.insufficientSpace(let needed, let available) {
            XCTAssertEqual(available, 0)
            XCTAssertGreaterThan(needed, 800_000_000)
        }
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
    }

    // Review focus 5: rebuilding into a folder that already has the app.
    func testExistingDestinationNeedsOverwrite() async throws {
        let gw = try makeWrap()
        let info = try await gw.inspect(gameFolder)
        let config = BuildConfig(name: "Hollow Thing", exe: "Hollow Thing.exe", destination: destination)
        let existing = try Fixtures.writeFile(destination, "Hollow Thing.app/old-marker")
        do {
            _ = try await collect(gw.build(info, config))
            XCTFail("expected destinationExists")
        } catch let error as GameWrapError {
            XCTAssertEqual(error, .destinationExists(destination.appendingPathComponent("Hollow Thing.app")))
        }
        _ = try await collect(gw.build(info, config, overwrite: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: existing.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Hollow Thing.app/Contents/Info.plist").path))
    }

    func testUnwritableDestination() async throws {
        let gw = try makeWrap()
        let info = try await gw.inspect(gameFolder)
        let missing = base.appendingPathComponent("does-not-exist")
        do {
            _ = try await collect(gw.build(info, BuildConfig(name: "G", exe: "Hollow Thing.exe", destination: missing)))
            XCTFail("expected destinationNotWritable")
        } catch let error as GameWrapError {
            XCTAssertEqual(error, .destinationNotWritable(missing))
        }
    }

    func testCustomIconAndGenericFallback() async throws {
        let runner = FakeProcessRunner()
        let gw = try makeWrap(runner: runner)
        let noIcon = base.appendingPathComponent("NoIcon")
        try Fixtures.writeExe(noIcon, "noicon.exe")
        let info = try await gw.inspect(noIcon)
        XCTAssertNil(info.iconPNG)
        _ = try await collect(gw.build(info, BuildConfig(name: "No Icon", exe: "noicon.exe", destination: destination)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("No Icon.app/Contents/Resources/AppIcon.icns").path))

        let custom = try Fixtures.writeFile(base, "custom.txt", "not an image")
        let info2 = try await gw.inspect(noIcon)
        do {
            _ = try await collect(gw.build(info2, BuildConfig(name: "Bad Icon", exe: "noicon.exe", icon: .custom(custom), destination: destination)))
            XCTFail("expected invalidIcon")
        } catch let error as GameWrapError {
            XCTAssertEqual(error, .invalidIcon)
        }
    }

    func testCancelDuringSigningCleansUp() async throws {
        let runner = FakeProcessRunner { tool, args in
            if tool == Tool.codesign { try await Task.sleep(nanoseconds: 10_000_000_000) }
            return try await FakeProcessRunner.realisticHandler(tool, args)
        }
        let gw = try makeWrap(runner: runner)
        let info = try await gw.inspect(gameFolder)
        let stream = gw.build(info, BuildConfig(name: "Hollow Thing", exe: "Hollow Thing.exe", destination: destination))
        let signing = expectation(description: "signing started")
        let consumer = Task {
            for try await event in stream where event == .step(.sign, .started) { signing.fulfill() }
        }
        await fulfillment(of: [signing], timeout: 10)
        consumer.cancel()
        _ = await consumer.result

        for _ in 0..<100 where !buildFolders(info).isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(buildFolders(info), [], "a cancelled build must delete its temporary folder")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Hollow Thing.app").path))
    }

    func testDiscardRemovesWorkDir() async throws {
        let gw = try makeWrap()
        let info = try await gw.inspect(gameFolder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: info.imported.workDir.path))
        gw.discard(info)
        XCTAssertFalse(FileManager.default.fileExists(atPath: info.imported.workDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: gameFolder.path), "discard never touches a folder source")
    }

    // Final review fix: cancelling and immediately building again must not break the new build.
    func testCancelThenImmediateRebuildSucceeds() async throws {
        let state = SecondBuildFlag()
        let runner = FakeProcessRunner { tool, args in
            // A slow-exiting hdiutil that ignores cancellation, and a slow signer for the second build.
            if tool == Tool.hdiutil, args.first == "create" { usleep(800_000) }   // blocking: cancellation can't shorten it
            if tool == Tool.codesign, state.isSet { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            return try await FakeProcessRunner.realisticHandler(tool, args)
        }
        let gw = try makeWrap(runner: runner)
        let info = try await gw.inspect(gameFolder)
        let first = gw.build(info, BuildConfig(name: "Hollow Thing", exe: "Hollow Thing.exe", output: .appAndDMG, destination: destination))
        let packaging = expectation(description: "packaging started")
        let consumer = Task {
            for try await event in first where event == .step(.package, .started) { packaging.fulfill() }
        }
        await fulfillment(of: [packaging], timeout: 10)
        consumer.cancel()
        state.set()
        let events = try await collect(gw.build(info, BuildConfig(name: "Hollow Thing", exe: "Hollow Thing.exe", destination: destination)))
        XCTAssertEqual(result(events)?.app, destination.appendingPathComponent("Hollow Thing.app").path)
    }

    // Final review fix: a loose .exe in Downloads (or Downloads itself) must not bundle the whole folder.
    func testRefusesPersonalFoldersAsGameRoot() async throws {
        let downloads = base.appendingPathComponent("Downloads")
        let exe = try Fixtures.writeExe(downloads, "game.exe")
        try Fixtures.writeFile(downloads, "tax-return.pdf")
        let gw = GameWrap(runner: FakeProcessRunner(), runtime: try FakeRuntime.make(in: base),
                          availableSpace: { _ in .max }, protectedFolders: [downloads])
        for source in [exe, downloads] {
            do {
                _ = try await gw.inspect(source)
                XCTFail("expected unsafeGameFolder for \(source.lastPathComponent)")
            } catch let error as GameWrapError {
                guard case .unsafeGameFolder = error else { return XCTFail("unexpected \(error)") }
            }
        }
    }
}

final class SecondBuildFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
