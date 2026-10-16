import Foundation

public enum Tool {
    public static let bsdtar = "/usr/bin/bsdtar"
    public static let ditto = "/usr/bin/ditto"
    public static let codesign = "/usr/bin/codesign"
    public static let hdiutil = "/usr/bin/hdiutil"
    public static let xattr = "/usr/bin/xattr"
    public static let iconutil = "/usr/bin/iconutil"
    public static let osascript = "/usr/bin/osascript"
    public static let zsh = "/bin/zsh"
}

public struct ProcessResult: Equatable, Sendable {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

/// Runs command-line tools. A non-zero exit throws `GameWrapError.toolFailed`.
public protocol ProcessRunner: Sendable {
    @discardableResult
    func run(_ tool: String, _ args: [String], cwd: URL?, env: [String: String]?) async throws -> ProcessResult
}

extension ProcessRunner {
    @discardableResult
    public func run(_ tool: String, _ args: [String]) async throws -> ProcessResult {
        try await run(tool, args, cwd: nil, env: nil)
    }
}

public struct SystemProcessRunner: ProcessRunner {
    public init() {}

    @discardableResult
    public func run(_ tool: String, _ args: [String], cwd: URL? = nil, env: [String: String]? = nil) async throws -> ProcessResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }
        if let env { process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let buffer = OutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { buffer.append($0.availableData) }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                process.terminationHandler = { finished in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    buffer.append(pipe.fileHandleForReading.readDataToEndOfFile())
                    let output = buffer.string
                    if finished.terminationStatus == 0 {
                        continuation.resume(returning: ProcessResult(status: 0, output: output))
                    } else {
                        continuation.resume(throwing: GameWrapError.toolFailed(
                            tool: URL(fileURLWithPath: tool).lastPathComponent,
                            status: finished.terminationStatus, output: output))
                    }
                }
                do {
                    try process.run()
                    // A cancel that landed before launch found nothing running to stop.
                    if Task.isCancelled { process.terminate() }
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); data.append(chunk); lock.unlock()
    }

    var string: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
