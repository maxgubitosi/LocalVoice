import XCTest
@testable import LocalVoice

final class RecordingHotkeyTests: XCTestCase {
    func testLegacyKeyCodeMigration() {
        XCTAssertEqual(RecordingHotkey.fromLegacyKeyCode(54), .rightCommand)
        XCTAssertEqual(RecordingHotkey.fromLegacyKeyCode(63), .function)
        XCTAssertEqual(RecordingHotkey.fromLegacyKeyCode(61), .rightOption)
        XCTAssertEqual(RecordingHotkey.fromLegacyKeyCode(62), .rightControl)
        XCTAssertNil(RecordingHotkey.fromLegacyKeyCode(12))
    }

    func testHotkeysExposeKeyCodeAndFlag() {
        XCTAssertEqual(RecordingHotkey.rightCommand.keyCode, 0x36)
        XCTAssertEqual(RecordingHotkey.function.keyCode, 0x3F)
        XCTAssertEqual(RecordingHotkey.rightOption.keyCode, 0x3D)
        XCTAssertEqual(RecordingHotkey.rightControl.keyCode, 0x3E)
    }
}

final class ActiveAppContextTests: XCTestCase {
    func testPromptDescriptionIncludesBrowserPage() {
        let context = ActiveAppContext(
            bundleID: "com.google.Chrome",
            name: "Google Chrome",
            browserPage: BrowserPageContext(
                title: "LocalVoice Pull Request",
                url: "https://github.com/example/localvoice/pull/12?token=secret#discussion"
            )
        )

        XCTAssertEqual(
            context.promptDescription,
            "Google Chrome - active page: LocalVoice Pull Request (https://github.com/example/localvoice/pull/12)"
        )
    }

    func testPromptDescriptionFallsBackToAppName() {
        let context = ActiveAppContext(
            bundleID: "com.apple.Notes",
            name: "Notes",
            browserPage: nil
        )

        XCTAssertEqual(context.promptDescription, "Notes")
    }

    func testBrowserPageContextCleansTitleAndURL() {
        let page = BrowserPageContext(
            title: "  Project\nNotes  ",
            url: "https://example.com/docs?id=123#top"
        )

        XCTAssertEqual(page.promptDescription, "Project Notes (https://example.com/docs)")
    }
}
