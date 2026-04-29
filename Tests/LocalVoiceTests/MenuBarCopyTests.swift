import XCTest
@testable import LocalVoice

final class MenuBarCopyTests: XCTestCase {
    func testTopLevelTitlesDoNotIncludeSelectedValues() {
        let titles = [
            MenuBarCopy.modeTitle,
            MenuBarCopy.languageTitle,
            MenuBarCopy.whisperTitle,
            MenuBarCopy.refineModelTitle,
            MenuBarCopy.promptTitle,
        ]

        XCTAssertEqual(titles, ["Mode", "Language", "Whisper", "Refine Model", "Prompt"])
        XCTAssertFalse(titles.contains { $0.contains(":") })
    }

    func testPromptHintIsShort() {
        XCTAssertEqual(MenuBarCopy.promptShortcutHint(), "Press 1-9 during recording")
    }
}
