import XCTest
@testable import GameWrapCore

final class IconExtractorTests: XCTestCase {
    func testPicksLargestPNGIcon() throws {
        let small = ImageFixtures.png(width: 16), large = ImageFixtures.png(width: 64)
        let exe = try Fixtures.writeExe(try tempDir(), "g.exe", resources: [
            PEFile.rtIcon: [1: small, 2: large],
            PEFile.rtGroupIcon: [1: ImageFixtures.groupIcon([(16, 1, small.count), (64, 2, large.count)])],
        ])
        let png = try XCTUnwrap(IconExtractor.largestIconPNG(exe: exe))
        XCTAssertEqual(ImageFixtures.size(ofPNG: png), 64)
    }

    func testDecodesBMPIcons() throws {
        let dib = ImageFixtures.dib(width: 32)
        let exe = try Fixtures.writeExe(try tempDir(), "g.exe", resources: [
            PEFile.rtIcon: [5: dib],
            PEFile.rtGroupIcon: [1: ImageFixtures.groupIcon([(32, 5, dib.count)])],
        ])
        let png = try XCTUnwrap(IconExtractor.largestIconPNG(exe: exe))
        XCTAssertEqual(ImageFixtures.size(ofPNG: png), 32)
    }

    func testExeWithoutIconReturnsNil() throws {
        let exe = try Fixtures.writeExe(try tempDir(), "g.exe")
        XCTAssertNil(IconExtractor.largestIconPNG(exe: exe))
    }

    func testMakesRealICNSFromImage() async throws {
        let out = try tempDir().appendingPathComponent("AppIcon.icns")
        try await IconExtractor(runner: SystemProcessRunner()).makeICNS(fromImageData: ImageFixtures.png(width: 256), to: out)
        let data = try Data(contentsOf: out)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "icns")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.deletingLastPathComponent().path), ["AppIcon.icns"])
    }

    func testMakesGenericICNS() async throws {
        let out = try tempDir().appendingPathComponent("AppIcon.icns")
        try await IconExtractor(runner: SystemProcessRunner()).makeGenericICNS(name: "Hyperballin", to: out)
        XCTAssertEqual(String(decoding: try Data(contentsOf: out).prefix(4), as: UTF8.self), "icns")
    }

    func testInvalidImageThrows() async throws {
        let out = try tempDir().appendingPathComponent("AppIcon.icns")
        do {
            try await IconExtractor(runner: SystemProcessRunner()).makeICNS(fromImageData: Data("nope".utf8), to: out)
            XCTFail("expected invalidIcon")
        } catch let error as GameWrapError {
            XCTAssertEqual(error, .invalidIcon)
        }
    }
}
