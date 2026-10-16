import AppKit
import XCTest
@testable import GameWrapApp

final class AppModelTests: XCTestCase {
    @MainActor
    func testStartingAnotherGameResetsPerGameOptionsAndDiagnostics() {
        let model = AppModel()
        model.name = "Previous game"
        model.argsText = "-dx11"
        model.advertiseAVX = false
        model.showFPS = true
        model.log = "Previous failure"
        model.confirmOverwrite = true
        model.startOver()
        XCTAssertEqual(model.name, "")
        XCTAssertEqual(model.argsText, "")
        XCTAssertTrue(model.advertiseAVX)
        XCTAssertFalse(model.showFPS)
        XCTAssertEqual(model.log, "")
        XCTAssertFalse(model.confirmOverwrite)
    }

    @MainActor
    func testUnreadableIconDoesNotReplaceCurrentIcon() {
        let model = AppModel()
        let preview = NSImage(size: NSSize(width: 32, height: 32))
        model.iconPreview = preview
        model.setCustomIcon(URL(fileURLWithPath: "/missing-gamewrap-test-icon.png"))
        XCTAssertNil(model.customIcon)
        XCTAssertTrue(model.iconPreview === preview)
        XCTAssertFalse(model.log.isEmpty)
    }
}
