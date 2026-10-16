import Foundation

public struct SourceInfo: Sendable {
    public let source: URL
    public let imported: ImportedSource
    /// Most likely game first; never empty.
    public let candidates: [ExeCandidate]
    public let redists: [String]
    /// Icon of the first candidate, as PNG.
    public let iconPNG: Data?
    public let sizeBytes: Int64

    public func iconPNG(forExe relativePath: String) -> Data? {
        IconExtractor.largestIconPNG(exe: imported.gameRoot.appendingPathComponent(relativePath))
    }
}

public enum BuildStep: String, CaseIterable, Sendable {
    case preflight, runtime, importSource, icon, assemble, sign, package, deliver

    public var title: String {
        switch self {
        case .preflight: return "Check disk space"
        case .runtime: return "Get Windows runtime"
        case .importSource: return "Import game"
        case .icon: return "Make icon"
        case .assemble: return "Assemble app"
        case .sign: return "Sign app"
        case .package: return "Create .dmg"
        case .deliver: return "Save to destination"
        }
    }
}

public enum StepState: Equatable, Sendable {
    case started, finished
}

public struct BuildResult: Equatable, Sendable {
    public let app: URL
    public let dmg: URL?
}

public enum BuildEvent: Equatable, Sendable {
    case step(BuildStep, StepState)
    case progress(Double)
    case log(String)
    case finished(BuildResult)
}

/// Sends each command and its output to the build log.
struct LoggingRunner: ProcessRunner {
    let base: ProcessRunner
    let emit: @Sendable (BuildEvent) -> Void

    func run(_ tool: String, _ args: [String], cwd: URL?, env: [String: String]?) async throws -> ProcessResult {
        emit(.log("$ " + ([URL(fileURLWithPath: tool).lastPathComponent] + args).joined(separator: " ")))
        do {
            let result = try await base.run(tool, args, cwd: cwd, env: env)
            if !result.output.isEmpty { emit(.log(result.output.trimmingCharacters(in: .newlines))) }
            return result
        } catch {
            if case GameWrapError.toolFailed(_, _, let output) = error { emit(.log(output.trimmingCharacters(in: .newlines))) }
            throw error
        }
    }
}

public final class GameWrap: Sendable {
    static let runtimeAllowance: Int64 = 800_000_000

    let runner: ProcessRunner
    public let runtime: RuntimeProviding
    let availableSpace: @Sendable (URL) -> Int64
    let protectedFolders: [URL]

    public static let freeSpace: @Sendable (URL) -> Int64 = { url in
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? .max
    }

    public init(runner: ProcessRunner = SystemProcessRunner(), runtime: RuntimeProviding = RuntimeManager(),
                availableSpace: @escaping @Sendable (URL) -> Int64 = GameWrap.freeSpace,
                protectedFolders: [URL] = GameWrap.defaultProtectedFolders) {
        self.runner = runner
        self.runtime = runtime
        self.availableSpace = availableSpace
        self.protectedFolders = protectedFolders
    }

    /// Folders that must never become a game root: bundling them would copy personal files.
    public static var defaultProtectedFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home] + ["Desktop", "Downloads", "Documents", "Library", "Applications", "Movies", "Music", "Pictures"].map { home.appendingPathComponent($0) }
            + ["/", "/Applications", "/Users", "/Volumes"].map { URL(fileURLWithPath: $0) }
    }

    /// Imports the source into a new work folder and detects exes, redists and the icon.
    public func inspect(_ source: URL) async throws -> SourceInfo {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("gamewrap-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            let imported = try await SourceImporter(runner: runner).importSource(source, workDir: work)
            let rootPath = Self.canonicalPath(imported.gameRoot)
            if protectedFolders.contains(where: { Self.canonicalPath($0) == rootPath }) {
                throw GameWrapError.unsafeGameFolder(imported.gameRoot)
            }
            let candidates = ExeDetector.candidates(in: imported.gameRoot, gameName: imported.suggestedName)
            guard let first = candidates.first else { throw GameWrapError.noExeFound }
            return SourceInfo(source: source, imported: imported, candidates: candidates,
                              redists: RedistDetector.redists(in: imported.gameRoot),
                              iconPNG: IconExtractor.largestIconPNG(exe: imported.gameRoot.appendingPathComponent(first.relativePath)),
                              sizeBytes: FileScan.totalSize(of: imported.gameRoot))
        } catch {
            try? fm.removeItem(at: work)
            throw error
        }
    }

    static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Deletes the work folder (and any extracted archive) created by `inspect`.
    public func discard(_ info: SourceInfo) {
        try? FileManager.default.removeItem(at: info.imported.workDir)
    }

    public func build(_ info: SourceInfo, _ config: BuildConfig, overwrite: Bool = false) -> AsyncThrowingStream<BuildEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await self.runBuild(info, config, overwrite: overwrite) { continuation.yield($0) }
                    continuation.yield(.finished(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runBuild(_ info: SourceInfo, _ config: BuildConfig, overwrite: Bool,
                          emit: @escaping @Sendable (BuildEvent) -> Void) async throws -> BuildResult {
        let fm = FileManager.default
        let runner = LoggingRunner(base: self.runner, emit: emit)
        // Each build gets its own folder, so a cancelled build that is still winding down
        // can't delete the files of the next one.
        let work = info.imported.workDir.appendingPathComponent("build-\(UUID().uuidString)")
        let root = work.appendingPathComponent("root")
        let fileName = BundleAssembler.bundleFileName(config.name)
        let icns = work.appendingPathComponent("AppIcon.icns")
        let dmgTemp = work.appendingPathComponent("\(fileName).dmg")
        defer { try? fm.removeItem(at: work) }
        let appDestination = config.destination.appendingPathComponent(fileName + ".app")
        let dmgDestination = config.output == .appAndDMG ? config.destination.appendingPathComponent(fileName + ".dmg") : nil
        let exeURL = info.imported.gameRoot.appendingPathComponent(config.exe)

        func step<T>(_ step: BuildStep, _ body: () async throws -> T) async throws -> T {
            try Task.checkCancellation()
            emit(.step(step, .started))
            let value = try await body()
            emit(.step(step, .finished))
            return value
        }

        try await step(.preflight) {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: config.destination.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  fm.isWritableFile(atPath: config.destination.path) else { throw GameWrapError.destinationNotWritable(config.destination) }
            guard fm.fileExists(atPath: exeURL.path) else { throw GameWrapError.noExeFound }
            if !overwrite {
                for url in [appDestination, dmgDestination].compactMap({ $0 }) where fm.fileExists(atPath: url.path) {
                    throw GameWrapError.destinationExists(url)
                }
            }
            let runtimeSize: Int64 = runtime.spec.id == DXMTRuntimeManager.runtimeID ? 2_000_000_000 : Self.runtimeAllowance
            let perCopy = info.sizeBytes + runtimeSize
            let outputSpace = config.output == .appAndDMG ? perCopy * 2 : perCopy
            let needed = outputSpace + (runtime.spec.id == DXMTRuntimeManager.runtimeID && !runtime.isInstalled() ? 2_000_000_000 : 0)
            let available = availableSpace(fm.temporaryDirectory)
            guard available >= needed else { throw GameWrapError.insufficientSpace(needed: needed, available: available) }
        }

        let wine = try await step(.runtime) { try await runtime.ensureInstalled { emit(.progress($0)) } }
        try await step(.importSource) {}   // done by inspect
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        try await step(.icon) {
            let extractor = IconExtractor(runner: runner)
            switch config.icon {
            case .custom(let url) where url.pathExtension.lowercased() == "icns":
                try fm.copyItem(at: url, to: icns)
            case .custom(let url):
                guard let data = try? Data(contentsOf: url) else { throw GameWrapError.invalidIcon }
                try await extractor.makeICNS(fromImageData: data, to: icns)
            case .extracted:
                if let png = IconExtractor.largestIconPNG(exe: exeURL) {
                    try await extractor.makeICNS(fromImageData: png, to: icns)
                } else {
                    try await extractor.makeGenericICNS(name: config.name, to: icns)
                }
            }
        }

        let manifest = GameManifest(config: config, redists: info.redists, runtimeID: runtime.spec.id)
        let app = try await step(.assemble) {
            try await BundleAssembler(runner: runner).assemble(manifest: manifest, gameRoot: info.imported.gameRoot, wine: wine, icns: icns, in: root)
        }
        try await step(.sign) { try await Signer(runner: runner).sign(app) }
        if dmgDestination != nil {
            try await step(.package) { try await DMGPackager(runner: runner).package(folder: root, volumeName: config.name, to: dmgTemp) }
        }

        return try await step(.deliver) {
            if overwrite {
                try? fm.removeItem(at: appDestination)
                if let dmgDestination { try? fm.removeItem(at: dmgDestination) }
            }
            try fm.moveItem(at: app, to: appDestination)
            if let dmgDestination { try fm.moveItem(at: dmgTemp, to: dmgDestination) }
            return BuildResult(app: appDestination, dmg: dmgDestination)
        }
    }
}
