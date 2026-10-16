import Foundation

public struct ExeCandidate: Equatable, Sendable, Identifiable {
    public var id: String { relativePath }
    public let relativePath: String
    public let size: Int64
    public let machine: PEMachine
    /// Crash handlers, installers and redistributables: listed last, never picked by default.
    public let isLikelyHelper: Bool
}

public enum ExeDetector {
    static let helperPrefixes = ["unitycrashhandler", "crashreport", "vc_redist", "dxsetup", "unins", "ue4prereqsetup", "ueprereqsetup"]
    static let helperWords = ["setup", "install"]

    /// Every Windows program under `root`, the most likely game first.
    public static func candidates(in root: URL, gameName: String) -> [ExeCandidate] {
        let wanted = Set([normalize(root.lastPathComponent), normalize(gameName)])
        let ranked: [(bucket: Int, candidate: ExeCandidate)] = FileScan.files(in: root) { $0.pathExtension.lowercased() == "exe" }
            .compactMap { file in
                guard let machine = PEFile.machine(of: file.url) else { return nil }
                let name = file.url.deletingPathExtension().lastPathComponent
                let lower = name.lowercased()
                let helper = helperPrefixes.contains { lower.hasPrefix($0) } || helperWords.contains { lower.contains($0) }
                let bucket: Int
                if helper { bucket = 3 }
                else if lower.hasSuffix("-win64-shipping") { bucket = 0 }
                else if !file.relativePath.contains("/") && wanted.contains(normalize(name)) { bucket = 1 }
                else { bucket = 2 }
                return (bucket, ExeCandidate(relativePath: file.relativePath, size: file.size, machine: machine, isLikelyHelper: helper))
            }
        return ranked
            .sorted { ($0.bucket, -$0.candidate.size, $0.candidate.relativePath) < ($1.bucket, -$1.candidate.size, $1.candidate.relativePath) }
            .map(\.candidate)
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

public enum RedistDetector {
    /// 64-bit Visual C++ runtime installers shipped with the game, relative to `root`.
    public static func redists(in root: URL) -> [String] {
        FileScan.files(in: root) { $0.lastPathComponent.lowercased() == "vc_redist.x64.exe" }
            .map(\.relativePath)
            .sorted()
    }
}
