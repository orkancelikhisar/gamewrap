import XCTest
@testable import GameWrapCore

final class PackagingTests: XCTestCase {
    func makeTinyApp(in dir: URL) throws -> URL {
        let app = dir.appendingPathComponent("Tiny.app")
        let exe = try Fixtures.writeFile(app, "Contents/MacOS/Tiny", "#!/bin/sh\necho hi\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        let plist: [String: Any] = ["CFBundleExecutable": "Tiny", "CFBundleIdentifier": "test.tiny", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    func testSignerRunsClearSignVerify() async throws {
        let app = URL(fileURLWithPath: "/tmp/X.app")
        let runner = FakeProcessRunner()
        try await Signer(runner: runner).sign(app)
        XCTAssertEqual(runner.calls, [
            .init(tool: Tool.xattr, args: ["-cr", app.path]),
            .init(tool: Tool.codesign, args: ["--force", "--deep", "-s", "-", app.path]),
            .init(tool: Tool.codesign, args: ["--verify", "--deep", app.path]),
        ])
    }

    func testSigningFailureBecomesSigningFailed() async {
        let runner = FakeProcessRunner { tool, _ in
            if tool == Tool.codesign { throw GameWrapError.toolFailed(tool: "codesign", status: 1, output: "detritus not allowed\n") }
            return ProcessResult(status: 0, output: "")
        }
        do {
            try await Signer(runner: runner).sign(URL(fileURLWithPath: "/tmp/X.app"))
            XCTFail("expected signingFailed")
        } catch let error as GameWrapError {
            XCTAssertEqual(error, .signingFailed("detritus not allowed"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRealSigningVerifies() async throws {
        let app = try makeTinyApp(in: try tempDir())
        try await Signer(runner: SystemProcessRunner()).sign(app)
        try await SystemProcessRunner().run(Tool.codesign, ["--verify", "--deep", "--strict", app.path])
    }

    func testPackagerArgumentsAndCleanup() async throws {
        let folder = try tempDir()
        _ = try makeTinyApp(in: folder)
        let output = try tempDir().appendingPathComponent("Tiny.dmg")
        let runner = FakeProcessRunner()
        try await DMGPackager(runner: runner).package(folder: folder, volumeName: "Tiny", to: output)
        XCTAssertEqual(runner.calls, [
            .init(tool: Tool.hdiutil, args: ["create", "-volname", "Tiny", "-srcfolder", folder.path, "-fs", "APFS", "-format", "ULMO", "-ov", output.path]),
            .init(tool: Tool.hdiutil, args: ["verify", output.path]),
        ])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Tiny.app"])
    }

    func testRealDMGIsCreated() async throws {
        let folder = try tempDir()
        _ = try makeTinyApp(in: folder)
        let output = try tempDir().appendingPathComponent("Tiny.dmg")
        try await DMGPackager(runner: SystemProcessRunner()).package(folder: folder, volumeName: "Tiny", to: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    func testPackagingFailureBecomesPackagingFailed() async throws {
        let runner = FakeProcessRunner { _, _ in throw GameWrapError.toolFailed(tool: "hdiutil", status: 1, output: "no space") }
        do {
            try await DMGPackager(runner: runner).package(folder: try tempDir(), volumeName: "T", to: URL(fileURLWithPath: "/tmp/t.dmg"))
            XCTFail("expected packagingFailed")
        } catch let error as GameWrapError {
            XCTAssertEqual(error, .packagingFailed("no space"))
        }
    }
}
