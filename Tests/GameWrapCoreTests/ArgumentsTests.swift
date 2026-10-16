import XCTest
@testable import GameWrapCore

final class ArgumentsTests: XCTestCase {
    func testSplitsOnSpacesAndKeepsQuotedGroups() {
        XCTAssertEqual(ArgumentSplitter.split(""), [])
        XCTAssertEqual(ArgumentSplitter.split("  -dx11   -windowed "), ["-dx11", "-windowed"])
        XCTAssertEqual(ArgumentSplitter.split(#"-name "O'Brien Two" -x"#), ["-name", "O'Brien Two", "-x"])
        XCTAssertEqual(ArgumentSplitter.split(#"--path="C:\Games\My Game""#), [#"--path=C:\Games\My Game"#])
        XCTAssertEqual(ArgumentSplitter.split(#""""#), [""])
    }
}
