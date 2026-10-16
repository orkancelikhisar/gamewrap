import XCTest
@testable import GameWrapCore

final class PEFileTests: XCTestCase {
    func testReadsMachineTypes() throws {
        XCTAssertEqual(try PEFile(data: PEBuilder.make(machine: 0x8664)).machine, .x64)
        XCTAssertEqual(try PEFile(data: PEBuilder.make(machine: 0x014C, pe32: true)).machine, .x86)
        XCTAssertEqual(try PEFile(data: PEBuilder.make(machine: 0xAA64)).machine, .arm64)
        XCTAssertEqual(try PEFile(data: PEBuilder.make(machine: 0x01C4)).machine, .other(0x01C4))
    }

    func testRejectsNonPEData() {
        XCTAssertThrowsError(try PEFile(data: Data("hello, not an exe".utf8)))
        XCTAssertThrowsError(try PEFile(data: Data()))
    }

    func testReadsResourcesByType() throws {
        let pe = try PEFile(data: PEBuilder.make(resources: [10: [7: Data("seven".utf8), 9: Data("nine".utf8)], 3: [1: Data("icon".utf8)]]))
        let rcdata = pe.resources(ofType: 10)
        XCTAssertEqual(rcdata.map(\.id), [7, 9])
        XCTAssertEqual(rcdata.map(\.data), [Data("seven".utf8), Data("nine".utf8)])
        XCTAssertEqual(pe.resources(ofType: 3).map(\.data), [Data("icon".utf8)])
        XCTAssertTrue(pe.resources(ofType: 14).isEmpty)
    }

    func testResourcesInPE32Files() throws {
        let pe = try PEFile(data: PEBuilder.make(machine: 0x014C, pe32: true, resources: [10: [1: Data("x".utf8)]]))
        XCTAssertEqual(pe.resources(ofType: 10).map(\.data), [Data("x".utf8)])
    }

    func testNoResourceSection() throws {
        XCTAssertTrue(try PEFile(data: PEBuilder.make()).resources(ofType: 3).isEmpty)
    }

    func testMachineOfFile() throws {
        let dir = try tempDir()
        let exe = dir.appendingPathComponent("a.exe")
        try PEBuilder.make(machine: 0x014C, pe32: true).write(to: exe)
        let text = dir.appendingPathComponent("b.exe")
        try Data("text".utf8).write(to: text)
        XCTAssertEqual(PEFile.machine(of: exe), .x86)
        XCTAssertNil(PEFile.machine(of: text))
    }

    // Final review fix: section fields near UInt32.max must not trap.
    func testHugeSectionAddressesDoNotCrash() throws {
        var data = PEBuilder.make(resources: [10: [1: Data("x".utf8)]])
        let sec = 68 + 20 + 240
        data.put32(sec + 8, 0x100)
        data.put32(sec + 12, 0xFFFF_FFF0)
        data.put32(68 + 20 + 112 + 16, 0xFFFF_FFF8)
        let pe = try PEFile(data: data)
        XCTAssertTrue(pe.resources(ofType: 10).isEmpty)
    }
}
