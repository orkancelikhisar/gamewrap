import XCTest
@testable import GameWrapCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesOutput() async throws {
        let result = try await SystemProcessRunner().run("/bin/echo", ["hi"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "hi\n")
    }

    func testNonZeroExitThrowsToolFailedWithCombinedOutput() async {
        do {
            _ = try await SystemProcessRunner().run("/bin/sh", ["-c", "echo boom >&2; exit 3"])
            XCTFail("expected an error")
        } catch GameWrapError.toolFailed(let tool, let status, let output) {
            XCTAssertEqual(tool, "sh")
            XCTAssertEqual(status, 3)
            XCTAssertEqual(output, "boom\n")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testPassesEnvironmentAndWorkingDirectory() async throws {
        let dir = try tempDir()
        let result = try await SystemProcessRunner().run("/bin/sh", ["-c", "echo $GW_TEST; pwd -P"], cwd: dir, env: ["GW_TEST": "x"])
        let lines = result.output.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "x")
        XCTAssertEqual(URL(fileURLWithPath: lines[1]).resolvingSymlinksInPath().path, dir.resolvingSymlinksInPath().path)
    }

    func testCancellationTerminatesTheProcess() async throws {
        let task = Task { try await SystemProcessRunner().run("/bin/sleep", ["30"]) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let start = Date()
        task.cancel()
        _ = try? await task.value
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    // Final review fix: a cancel that arrives before the process starts must still stop it.
    func testCancellationBeforeLaunchStopsTheProcess() async throws {
        let start = Date()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SystemProcessRunner().run("/bin/sleep", ["30"])
        }
        _ = try? await task.value
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
