import Foundation

public enum GameWrapError: Error, Equatable, LocalizedError {
    case unsupportedSource(URL)
    case importFailed(String)
    case noExeFound
    case insufficientSpace(needed: Int64, available: Int64)
    case runtimeDownloadFailed(String)
    case runtimeChecksumMismatch
    case signingFailed(String)
    case packagingFailed(String)
    case destinationExists(URL)
    case destinationNotWritable(URL)
    case invalidIcon
    case unsafeGameFolder(URL)
    case toolFailed(tool: String, status: Int32, output: String)

    public var message: String {
        switch self {
        case .unsupportedSource: return "That file isn't a game GameWrap can read."
        case .importFailed: return "The archive couldn't be unpacked."
        case .noExeFound: return "No Windows program was found in it."
        case .insufficientSpace: return "There isn't enough free disk space to build this."
        case .runtimeDownloadFailed: return "The Windows runtime couldn't be downloaded."
        case .runtimeChecksumMismatch: return "The downloaded runtime didn't match the expected file."
        case .signingFailed: return "The app couldn't be signed."
        case .packagingFailed: return "The .dmg couldn't be created."
        case .destinationExists(let url): return "\(url.lastPathComponent) already exists in that folder."
        case .destinationNotWritable(let url): return "GameWrap can't save to \(url.path)."
        case .invalidIcon: return "That image can't be used as an icon."
        case .unsafeGameFolder(let url): return "That would put your whole \(url.lastPathComponent) folder into the app."
        case .toolFailed(let tool, let status, _): return "\(tool) failed (exit \(status))."
        }
    }

    public var suggestion: String {
        switch self {
        case .unsupportedSource: return "Drop an .exe, .rar, .zip, .7z or a game folder."
        case .importFailed(let detail): return "It may be damaged or password-protected. Unpack it yourself and drop the folder instead.\(Self.detail(detail))"
        case .noExeFound: return "Check that the folder contains the game's .exe file."
        case .insufficientSpace(let needed, let available):
            return "Free up \(ByteCountFormatter.string(fromByteCount: needed - available, countStyle: .file)) and try again."
        case .runtimeDownloadFailed(let detail): return "Check your internet connection and try again.\(Self.detail(detail))"
        case .runtimeChecksumMismatch: return "Try the download again. If it keeps failing, the release may have changed."
        case .signingFailed(let detail): return "This is usually a permissions problem. Try another destination.\(Self.detail(detail))"
        case .packagingFailed(let detail): return "Check free disk space and try again.\(Self.detail(detail))"
        case .destinationExists: return "Replace it, or choose another destination."
        case .destinationNotWritable: return "Choose a folder you can write to, such as Downloads."
        case .invalidIcon: return "Choose a PNG, JPEG or .icns file."
        case .unsafeGameFolder: return "Move the game into its own folder and drop that folder instead."
        case .toolFailed: return "See the log for details."
        }
    }

    public var errorDescription: String? { message }

    private static func detail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : " Details: \(trimmed)"
    }
}
