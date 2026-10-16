import XCTest
@testable import GameWrapCore

final class DXMTRuntimeTests: XCTestCase {
    func testRealDXMTInstallerAndGameBuild() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let archives = env["GAMEWRAP_DXMT_ARCHIVES"], let game = env["GAMEWRAP_DXMT_GAME"] else {
            throw XCTSkip("Set GAMEWRAP_DXMT_ARCHIVES and GAMEWRAP_DXMT_GAME for real runtime acceptance")
        }
        let names = ["wine.tar.xz", "dxmt.tar.gz", "dependencies.tar.xz"]
        let inputs = zip(DXMTRuntimeManager.archives, names).map { spec, name in
            RuntimeSpec(id: spec.id, url: URL(fileURLWithPath: archives).appendingPathComponent(name),
                        sha256: spec.sha256, downloadSize: spec.downloadSize)
        }
        let runtime = DXMTRuntimeManager(root: RuntimeManager.defaultRoot, inputs: inputs, runner: SystemProcessRunner())
        _ = try await runtime.ensureInstalled { _ in }
        XCTAssertTrue(runtime.isInstalled())
        let wrapper = GameWrap(runtime: runtime)
        let info = try await wrapper.inspect(URL(fileURLWithPath: game))
        defer { wrapper.discard(info) }
        let destination = URL(fileURLWithPath: "/tmp/gamewrap-integrated-dxmt")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let config = BuildConfig(name: "OFFRECORD Integrated DXMT", exe: info.candidates[0].relativePath, destination: destination)
        var result: BuildResult?
        for try await event in wrapper.build(info, config) {
            if case .finished(let built) = event { result = built }
        }
        let app = try XCTUnwrap(result?.app)
        try await SystemProcessRunner().run("/usr/bin/codesign", ["--verify", app.path])
        let manifest = try JSONDecoder().decode(GameManifest.self, from: Data(contentsOf: app.appendingPathComponent("Contents/Resources/gamewrap.json")))
        XCTAssertEqual(manifest.runtime, DXMTRuntimeManager.runtimeID)
        XCTAssertNil(manifest.env["WINEMSYNC"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/wine/COPYING.LIB").path))
    }

    func fixtureInputs(missingDXGI: Bool = false) async throws -> [RuntimeSpec] {
        var specs: [RuntimeSpec] = []
        for index in 0..<3 {
            let source = try tempDir()
            if index == 0 {
                for file in ["bin/wine", "bin/wineserver", "lib/wine/x86_64-unix/winemac.so"] {
                    try Fixtures.writeFile(source, "Wine.app/Contents/Resources/wine/" + file)
                }
            } else if index == 1 {
                for file in ["x86_64-unix/winemetal.so", "x86_64-windows/winemetal.dll", "x86_64-windows/d3d11.dll", "x86_64-windows/d3d10core.dll"] + (missingDXGI ? [] : ["x86_64-windows/dxgi.dll"]) {
                    try Fixtures.writeFile(source, "v0.80/" + file, "DXMT")
                }
            } else {
                try Fixtures.writeFile(source, "Wine.app/Contents/Resources/wine/bin/wine")
                try Fixtures.writeFile(source, "Wine.app/Contents/Resources/wine/lib/libinotify.0.dylib", "dependency")
            }
            let archive = try tempDir().appendingPathComponent("runtime.tar")
            try await SystemProcessRunner().run(Tool.bsdtar, ["-cf", archive.path, "-C", source.path, "."])
            specs.append(RuntimeSpec(id: "\(index)", url: archive, sha256: try RuntimeManager.sha256(of: archive), downloadSize: 1))
        }
        return specs
    }

    func testComposesVerifiedArchivesAndReusesCompleteCache() async throws {
        let inputs = try await fixtureInputs()
        let manager = DXMTRuntimeManager(root: try tempDir(), inputs: inputs, runner: SystemProcessRunner())
        let runtime = try await manager.ensureInstalled { _ in }
        XCTAssertTrue(manager.isInstalled())
        XCTAssertEqual(try String(contentsOf: runtime.appendingPathComponent("lib/wine/x86_64-windows/dxgi.dll")), "DXMT")
        XCTAssertEqual(try String(contentsOf: runtime.appendingPathComponent("lib/libinotify.0.dylib")), "dependency")
        for input in inputs { try FileManager.default.removeItem(at: input.url) }
        _ = try await manager.ensureInstalled { _ in }
    }

    func testBadChecksumLeavesNoInstalledRuntime() async throws {
        var inputs = try await fixtureInputs()
        let item = inputs[1]
        inputs[1] = RuntimeSpec(id: item.id, url: item.url, sha256: String(repeating: "0", count: 64), downloadSize: 1)
        let root = try tempDir()
        let manager = DXMTRuntimeManager(root: root, inputs: inputs, runner: SystemProcessRunner())
        do { _ = try await manager.ensureInstalled { _ in }; XCTFail("Expected checksum failure") }
        catch let error as GameWrapError { XCTAssertEqual(error, .runtimeChecksumMismatch) }
        XCTAssertFalse(manager.isInstalled())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testMissingGraphicsDLLCannotBecomeAnInstalledCache() async throws {
        let manager = DXMTRuntimeManager(root: try tempDir(), inputs: try await fixtureInputs(missingDXGI: true), runner: SystemProcessRunner())
        do { _ = try await manager.ensureInstalled { _ in }; XCTFail("Expected missing graphics DLL failure") }
        catch { XCTAssertFalse(manager.isInstalled()) }
    }
}
