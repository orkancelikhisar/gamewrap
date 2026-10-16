import XCTest
@testable import GameWrapCore

final class ExeDetectorTests: XCTestCase {
    func testUnrealShippingExeComesFirst() throws {
        let root = try tempDir().appendingPathComponent("Windows")
        try Fixtures.writeExe(root, "project_garden.exe", padTo: 300_000)
        try Fixtures.writeExe(root, "project_garden/Binaries/Win64/project_garden-Win64-Shipping.exe", padTo: 100_000)
        try Fixtures.writeExe(root, "Engine/Extras/Redist/en-us/vc_redist.x64.exe", padTo: 900_000)
        let paths = ExeDetector.candidates(in: root, gameName: "Hyperballin").map(\.relativePath)
        XCTAssertEqual(paths, [
            "project_garden/Binaries/Win64/project_garden-Win64-Shipping.exe",
            "project_garden.exe",
            "Engine/Extras/Redist/en-us/vc_redist.x64.exe",
        ])
    }

    func testUnityExeMatchingGameNameBeatsBiggerHelpers() throws {
        let root = try tempDir().appendingPathComponent("Hollow Thing")
        try Fixtures.writeExe(root, "Hollow Thing.exe", padTo: 1_000)
        try Fixtures.writeExe(root, "UnityCrashHandler64.exe", padTo: 2_000_000)
        try Fixtures.writeExe(root, "MonoBleedingEdge/EmbedRuntime/mono.exe", padTo: 3_000_000)
        let candidates = ExeDetector.candidates(in: root, gameName: "Hollow Thing")
        XCTAssertEqual(candidates.first?.relativePath, "Hollow Thing.exe")
        XCTAssertEqual(candidates.last?.relativePath, "UnityCrashHandler64.exe")
        XCTAssertTrue(candidates.last!.isLikelyHelper)
        XCTAssertFalse(candidates.first!.isLikelyHelper)
    }

    func testGenericLayoutPrefersLargestExe() throws {
        let root = try tempDir()
        try Fixtures.writeExe(root, "bin/small.exe", padTo: 1_000)
        try Fixtures.writeExe(root, "bin/big.exe", padTo: 50_000)
        try Fixtures.writeExe(root, "setup.exe", padTo: 90_000)
        try Fixtures.writeExe(root, "unins000.exe", padTo: 90_000)
        let paths = ExeDetector.candidates(in: root, gameName: "Whatever").map(\.relativePath)
        XCTAssertEqual(Array(paths.prefix(2)), ["bin/big.exe", "bin/small.exe"])
        XCTAssertEqual(Set(paths.suffix(2)), ["setup.exe", "unins000.exe"])
    }

    // Review focus 2: uppercase extensions are found, non-PE ".exe" files are skipped.
    func testUppercaseExtensionAndNonPEFiles() throws {
        let root = try tempDir()
        try Fixtures.writeExe(root, "GAME.EXE", padTo: 5_000)
        try Fixtures.writeFile(root, "notes.exe", "this is not a program")
        let candidates = ExeDetector.candidates(in: root, gameName: "Game")
        XCTAssertEqual(candidates.map(\.relativePath), ["GAME.EXE"])
        XCTAssertEqual(candidates.first?.machine, .x64)
    }

    func testReportsThirtyTwoBitExes() throws {
        let root = try tempDir()
        try Fixtures.writeExe(root, "old.exe", machine: 0x014C)
        XCTAssertEqual(ExeDetector.candidates(in: root, gameName: "old").first?.machine, .x86)
    }

    func testEmptyFolderHasNoCandidates() throws {
        XCTAssertTrue(ExeDetector.candidates(in: try tempDir(), gameName: "x").isEmpty)
    }

    func testFindsRedistsInKnownLayouts() throws {
        let root = try tempDir()
        try Fixtures.writeExe(root, "Engine/Extras/Redist/en-us/vc_redist.x64.exe")
        try Fixtures.writeExe(root, "_CommonRedist/vcredist/2019/VC_redist.x64.exe")
        try Fixtures.writeExe(root, "_CommonRedist/vcredist/2019/VC_redist.x86.exe")
        XCTAssertEqual(RedistDetector.redists(in: root), [
            "Engine/Extras/Redist/en-us/vc_redist.x64.exe",
            "_CommonRedist/vcredist/2019/VC_redist.x64.exe",
        ])
    }

    func testTotalSize() throws {
        let root = try tempDir()
        try Fixtures.writeFile(root, "a", String(repeating: "x", count: 100))
        try Fixtures.writeFile(root, "d/b", String(repeating: "y", count: 50))
        XCTAssertEqual(FileScan.totalSize(of: root), 150)
    }
}
