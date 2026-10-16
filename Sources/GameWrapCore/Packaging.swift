import Foundation

public struct Signer: Sendable {
    let runner: ProcessRunner

    public init(runner: ProcessRunner) {
        self.runner = runner
    }

    /// Ad-hoc signs the app. Attributes are cleared first because codesign rejects File Provider metadata.
    public func sign(_ app: URL) async throws {
        do {
            try await runner.run(Tool.xattr, ["-cr", app.path])
            try await runner.run(Tool.codesign, ["--force", "--deep", "-s", "-", app.path])
            try await runner.run(Tool.codesign, ["--verify", "--deep", app.path])
        } catch GameWrapError.toolFailed(_, _, let output) {
            throw GameWrapError.signingFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

public struct DMGPackager: Sendable {
    let runner: ProcessRunner

    public init(runner: ProcessRunner) {
        self.runner = runner
    }

    /// Creates a compressed APFS image of `folder` (which holds the .app) with an Applications shortcut.
    public func package(folder: URL, volumeName: String, to output: URL) async throws {
        let fm = FileManager.default
        let shortcut = folder.appendingPathComponent("Applications")
        try? fm.removeItem(at: shortcut)
        try fm.createSymbolicLink(at: shortcut, withDestinationURL: URL(fileURLWithPath: "/Applications"))
        defer { try? fm.removeItem(at: shortcut) }
        do {
            try await runner.run(Tool.hdiutil, ["create", "-volname", volumeName, "-srcfolder", folder.path,
                                                "-fs", "APFS", "-format", "ULMO", "-ov", output.path])
            try await runner.run(Tool.hdiutil, ["verify", output.path])
        } catch GameWrapError.toolFailed(_, _, let detail) {
            throw GameWrapError.packagingFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
