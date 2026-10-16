import XCTest
@testable import GameWrapCore

final class ModelsTests: XCTestCase {
    func testManifestEncodesExactlyTheSpecKeys() throws {
        let m = GameManifest(name: "Hyperballin", exe: "a/b.exe", args: ["-dx11"], redists: ["r/vc_redist.x64.exe"],
                             env: ["WINEMSYNC": "1"], showFPS: false, runtime: "gptk-3.0-3")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: m.encoded()) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["schema", "name", "exe", "args", "redists", "env", "showFPS", "runtime"])
        XCTAssertEqual(json["schema"] as? Int, 1)
        XCTAssertEqual(try JSONDecoder().decode(GameManifest.self, from: m.encoded()), m)
    }

    func testManifestFromConfigSetsEnvironment() {
        var config = BuildConfig(name: "G", exe: "g.exe", destination: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(GameManifest(config: config, redists: [], runtimeID: "rt").env,
                       ["WINEMSYNC": "1", "ROSETTA_ADVERTISE_AVX": "1"])
        config.advertiseAVX = false
        config.showFPS = true
        config.args = ["-dx11"]
        let m = GameManifest(config: config, redists: ["x/vc_redist.x64.exe"], runtimeID: "rt")
        XCTAssertEqual(m.env, ["WINEMSYNC": "1"])
        XCTAssertTrue(m.showFPS)
        XCTAssertEqual(m.args, ["-dx11"])
        XCTAssertEqual(m.redists, ["x/vc_redist.x64.exe"])
        XCTAssertEqual(m.runtime, "rt")
    }

    func testEveryErrorHasMessageAndSuggestion() {
        let url = URL(fileURLWithPath: "/tmp/x")
        let all: [GameWrapError] = [
            .unsupportedSource(url), .importFailed("d"), .noExeFound,
            .insufficientSpace(needed: 2_000_000_000, available: 1_000_000_000),
            .runtimeDownloadFailed("d"), .runtimeChecksumMismatch, .signingFailed("d"), .packagingFailed("d"),
            .destinationExists(url), .destinationNotWritable(url), .invalidIcon, .unsafeGameFolder(url),
            .toolFailed(tool: "codesign", status: 1, output: "o"),
        ]
        for error in all {
            XCTAssertFalse(error.message.isEmpty, "\(error)")
            XCTAssertFalse(error.suggestion.isEmpty, "\(error)")
            XCTAssertEqual(error.errorDescription, error.message)
        }
    }
}
