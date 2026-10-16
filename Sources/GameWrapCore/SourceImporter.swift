import Foundation

public struct ImportedSource: Equatable, Sendable {
    /// Folder that contains the game's files (read-only for folder and .exe sources).
    public let gameRoot: URL
    /// Temporary folder owned by this build session.
    public let workDir: URL
    public let suggestedName: String
}

public struct SourceImporter: Sendable {
    static let archiveExtensions: Set<String> = ["rar", "zip", "7z"]
    static let junk: Set<String> = ["__MACOSX", ".DS_Store"]

    let runner: ProcessRunner

    public init(runner: ProcessRunner) {
        self.runner = runner
    }

    public func importSource(_ source: URL, workDir: URL) async throws -> ImportedSource {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else { throw GameWrapError.unsupportedSource(source) }
        if isDirectory.boolValue {
            return ImportedSource(gameRoot: source, workDir: workDir, suggestedName: source.lastPathComponent)
        }

        let ext = source.pathExtension.lowercased()
        let baseName = source.deletingPathExtension().lastPathComponent
        if ext == "exe" {
            return ImportedSource(gameRoot: source.deletingLastPathComponent(), workDir: workDir, suggestedName: baseName)
        }
        guard Self.archiveExtensions.contains(ext) else { throw GameWrapError.unsupportedSource(source) }

        let destination = workDir.appendingPathComponent("source")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            try await runner.run(Tool.bsdtar, ["-xf", source.path, "-C", destination.path])
        } catch GameWrapError.toolFailed(_, _, let output) {
            throw GameWrapError.importFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ImportedSource(gameRoot: try Self.descendSingleFolders(destination), workDir: workDir, suggestedName: baseName)
    }

    /// Steps into a folder for as long as it's the only meaningful item, e.g. "Game v1/Windows".
    static func descendSingleFolders(_ folder: URL) throws -> URL {
        var current = folder
        while true {
            let items = try FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { !junk.contains($0.lastPathComponent) }
            guard items.count == 1, (try? items[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return current }
            current = items[0]
        }
    }
}
