import Foundation

public enum RuntimeProfile: String, CaseIterable, Sendable {
    case standard, unity6
    public var title: String { self == .standard ? "Standard (D3DMetal)" : "Unity 6 / DXMT (experimental)" }
    public var downloadSize: String { self == .standard ? "240 MB" : "491 MB" }
    public var manager: any RuntimeProviding {
        switch self {
        case .standard: return RuntimeManager()
        case .unity6: return DXMTRuntimeManager()
        }
    }
}

/// The exact opt-in runtime combination used to verify OFFRECORD startup.
/// Every archive is pinned and verified before extraction; only a completed cache is reused.
public struct DXMTRuntimeManager: RuntimeProviding {
    public static let runtimeID = "wine-dxmt-11.8-0.80-v1"
    public static let archives: [RuntimeSpec] = [
        RuntimeSpec(id: "wine", url: URL(string: "https://github.com/zzzz465/homebrew-wine-dxmt/releases/download/v11.8_mm1/wine-staging-11.8_mm1-osx64.tar.xz")!, sha256: "236e517c12b8adf2092607742c4337632f7b03ffc06e4341bc5fc0a8f0160a9f", downloadSize: 280_782_744),
        RuntimeSpec(id: "dxmt", url: URL(string: "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz")!, sha256: "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d", downloadSize: 18_681_669),
        RuntimeSpec(id: "dependencies", url: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-devel-11.18-osx64.tar.xz")!, sha256: "aa0ea4c82e636ae7bca2076387cb0a5affa26509ad13f119ecd0d62bd7ba6f82", downloadSize: 190_974_384)
    ]
    public var spec: RuntimeSpec {
        RuntimeSpec(id: Self.runtimeID, url: inputs[0].url, sha256: inputs[0].sha256,
                    downloadSize: inputs.reduce(0) { $0 + $1.downloadSize })
    }
    public let root: URL
    let inputs: [RuntimeSpec]
    let runner: any ProcessRunner
    public init(root: URL = RuntimeManager.defaultRoot) {
        self.init(root: root, inputs: Self.archives, runner: SystemProcessRunner())
    }
    init(root: URL, inputs: [RuntimeSpec], runner: any ProcessRunner) {
        self.root = root; self.inputs = inputs; self.runner = runner
    }
    public var wineURL: URL { root.appendingPathComponent(Self.runtimeID).appendingPathComponent("wine") }
    public func isInstalled() -> Bool { Self.isValid(wineURL) }
    static func isValid(_ wine: URL) -> Bool {
        [".gamewrap-dxmt-ready", "bin/wine", "bin/wineserver", "lib/wine/x86_64-unix/winemetal.so",
         "lib/wine/x86_64-windows/winemetal.dll", "lib/wine/x86_64-windows/d3d11.dll",
         "lib/wine/x86_64-windows/dxgi.dll", "lib/wine/x86_64-windows/d3d10core.dll", "lib/libinotify.0.dylib"]
            .allSatisfy { FileManager.default.fileExists(atPath: wine.appendingPathComponent($0).path) }
    }
    public func ensureInstalled(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if isInstalled() { progress(1); return wineURL }
        return try await InstallGate.shared.run(key: wineURL.path) { try await install(progress: progress) }
    }
    private func install(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if isInstalled() { progress(1); return wineURL }
        let fm = FileManager.default
        let partial = root.appendingPathComponent(".partial-\(Self.runtimeID)")
        try? fm.removeItem(at: partial)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: partial) }
        var folders: [URL] = []
        for (index, input) in inputs.enumerated() {
            try Task.checkCancellation()
            let archive = partial.appendingPathComponent("\(index).archive")
            do {
                try await Downloader.download(input.url, to: archive) { value in
                    progress((Double(index) + value) / Double(inputs.count))
                }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw GameWrapError.runtimeDownloadFailed(error.localizedDescription)
            }
            guard try RuntimeManager.sha256(of: archive) == input.sha256 else { throw GameWrapError.runtimeChecksumMismatch }
            let folder = partial.appendingPathComponent("extracted-\(index)")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try await runner.run(Tool.bsdtar, ["-xf", archive.path, "-C", folder.path])
            try fm.removeItem(at: archive)
            folders.append(folder)
        }
        guard folders.count == 3,
              let wine = Self.find("bin/wine", in: folders[0]),
              let dxmt = Self.find("x86_64-unix/winemetal.so", in: folders[1]),
              let dependencies = Self.find("bin/wine", in: folders[2]) else {
            throw GameWrapError.runtimeDownloadFailed("The DXMT runtime archives are incomplete.")
        }
        let lib = wine.appendingPathComponent("lib")
        for file in try fm.contentsOfDirectory(at: dependencies.appendingPathComponent("lib"), includingPropertiesForKeys: nil)
            where file.pathExtension == "dylib" && !fm.fileExists(atPath: lib.appendingPathComponent(file.lastPathComponent).path) {
            // Dereference symlinks so this runtime cannot refer back to the extraction folder.
            try fm.copyItem(at: file.resolvingSymlinksInPath(), to: lib.appendingPathComponent(file.lastPathComponent))
        }
        for file in ["x86_64-unix/winemetal.so", "x86_64-windows/winemetal.dll", "x86_64-windows/d3d11.dll", "x86_64-windows/dxgi.dll", "x86_64-windows/d3d10core.dll"] {
            let target = lib.appendingPathComponent("wine/" + file)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: dxmt.appendingPathComponent(file), to: target)
        }
        try Data("Wine 11.8_mm1 + DXMT 0.80 + Wine 11.18 dependencies\n".utf8).write(to: wine.appendingPathComponent(".gamewrap-dxmt-ready"))
        let license = Bundle.module.url(forResource: "LGPL-2.1", withExtension: "txt")!
        try fm.copyItem(at: license, to: wine.appendingPathComponent("COPYING.LIB"))
        try Data(BundleAssembler.dxmtNotice.utf8).write(to: wine.appendingPathComponent("LICENSE-NOTICE.txt"))
        guard Self.isValid(wine) else { throw GameWrapError.runtimeDownloadFailed("The assembled DXMT runtime is incomplete.") }
        try Task.checkCancellation()
        let installed = wineURL.deletingLastPathComponent()
        try? fm.removeItem(at: installed)
        try fm.createDirectory(at: installed, withIntermediateDirectories: true)
        try fm.moveItem(at: wine, to: wineURL)
        progress(1)
        return wineURL
    }
    static func find(_ required: String, in folder: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent(required).path) { return folder }
        guard let files = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in files where fm.fileExists(atPath: url.appendingPathComponent(required).path) { return url }
        return nil
    }
}
