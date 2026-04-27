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
