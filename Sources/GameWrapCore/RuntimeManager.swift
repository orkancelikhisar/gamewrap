import CryptoKit
import Foundation

public struct RuntimeSpec: Equatable, Sendable {
    public let id: String
    public let url: URL
    public let sha256: String
    public let downloadSize: Int64

    public init(id: String, url: URL, sha256: String, downloadSize: Int64) {
        self.id = id
        self.url = url
        self.sha256 = sha256
        self.downloadSize = downloadSize
    }

    /// Apple's Game Porting Toolkit 3.0 (Wine + D3DMetal), as packaged by Gcenx.
    public static let gptk303 = RuntimeSpec(
        id: "gptk-3.0-3",
        url: URL(string: "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz")!,
        sha256: "d377683937340f914823dbb2e1252b329cbf834ff58907d0293db8cebf0e392e",
        downloadSize: 239_000_000)
}

public protocol RuntimeProviding: Sendable {
    var spec: RuntimeSpec { get }
    func isInstalled() -> Bool
    /// Returns the local `wine` folder, downloading and unpacking it first if needed.
    func ensureInstalled(progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

public struct RuntimeManager: RuntimeProviding {
    public let spec: RuntimeSpec
    public let root: URL
    let runner: ProcessRunner

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameWrap/runtimes")
    }

    public init(spec: RuntimeSpec = .gptk303, root: URL = RuntimeManager.defaultRoot, runner: ProcessRunner = SystemProcessRunner()) {
        self.spec = spec
        self.root = root
        self.runner = runner
    }

    public var wineURL: URL {
        root.appendingPathComponent(spec.id).appendingPathComponent("wine")
    }

    public func isInstalled() -> Bool {
        Self.isValidWine(wineURL)
    }

    public func ensureInstalled(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if isInstalled() {
            progress(1)
            return wineURL
        }
        // One install per runtime folder at a time; later callers wait for the running one.
        return try await InstallGate.shared.run(key: wineURL.path) { try await install(progress: progress) }
    }

    private func install(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if isInstalled() {
            progress(1)
            return wineURL
        }
        let fm = FileManager.default
        let partial = root.appendingPathComponent(".partial-\(spec.id)")
        try? fm.removeItem(at: partial)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: partial) }

        let archive = partial.appendingPathComponent("runtime.tar.xz")
        do {
            try await Downloader.download(spec.url, to: archive, progress: progress)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw GameWrapError.runtimeDownloadFailed(error.localizedDescription)
        }
        guard try Self.sha256(of: archive) == spec.sha256 else { throw GameWrapError.runtimeChecksumMismatch }

        let extracted = partial.appendingPathComponent("extracted")
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        do {
            try await runner.run(Tool.bsdtar, ["-xf", archive.path, "-C", extracted.path])
        } catch {
            throw GameWrapError.runtimeDownloadFailed("The runtime archive couldn't be unpacked.")
        }
        guard let wine = Self.findWine(in: extracted) else {
            throw GameWrapError.runtimeDownloadFailed("The runtime archive doesn't contain Wine with D3DMetal.")
        }

        let installDir = wineURL.deletingLastPathComponent()
        try? fm.removeItem(at: installDir)
        try fm.createDirectory(at: installDir, withIntermediateDirectories: true)
        try fm.moveItem(at: wine, to: wineURL)
        progress(1)
        return wineURL
    }

    static func isValidWine(_ wine: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: wine.appendingPathComponent("bin/wine64").path)
            && fm.fileExists(atPath: wine.appendingPathComponent("lib/external/D3DMetal.framework").path)
    }

    static func findWine(in folder: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == "wine" && isValidWine(url) {
            return url
        }
        return nil
    }

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

actor InstallGate {
    static let shared = InstallGate()
    private var running: [String: Task<URL, Error>] = [:]

    func run(key: String, _ work: @escaping @Sendable () async throws -> URL) async throws -> URL {
        if let existing = running[key] { return try await existing.value }
        let task = Task { try await work() }
        running[key] = task
        defer { running[key] = nil }
        return try await task.value
    }
}

enum Downloader {
    static func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        if url.isFileURL {
            try FileManager.default.copyItem(at: url, to: destination)
            progress(1)
            return
        }
        let box = DownloadBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let task = URLSession.shared.downloadTask(with: url) { temporary, response, error in
                    if let error { continuation.resume(throwing: error); return }
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        continuation.resume(throwing: URLError(.badServerResponse)); return
                    }
                    guard let temporary else { continuation.resume(throwing: URLError(.unknown)); return }
                    do {
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.moveItem(at: temporary, to: destination)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.observation = task.progress.observe(\.fractionCompleted) { p, _ in progress(p.fractionCompleted) }
                box.task = task
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
        box.observation = nil
    }
}

final class DownloadBox: @unchecked Sendable {
    var task: URLSessionDownloadTask?
    var observation: NSKeyValueObservation?
}
