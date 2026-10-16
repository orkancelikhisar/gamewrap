import Foundation

struct ScannedFile {
    let url: URL
    let relativePath: String
    let size: Int64
}

enum FileScan {
    /// Regular, non-hidden files under `root` that pass `include`, with paths relative to `root`.
    static func files(in root: URL, where include: (URL) -> Bool) -> [ScannedFile] {
        let basePath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var result: [ScannedFile] = []
        for case let url as URL in enumerator {
            guard include(url), let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            result.append(ScannedFile(url: url, relativePath: relativePath(of: url, base: basePath), size: Int64(values.fileSize ?? 0)))
        }
        return result
    }

    static func totalSize(of root: URL) -> Int64 {
        files(in: root) { _ in true }.reduce(0) { $0 + $1.size }
    }

    private static func relativePath(of url: URL, base: String) -> String {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : url.lastPathComponent
    }
}
