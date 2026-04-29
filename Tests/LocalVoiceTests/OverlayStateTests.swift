import XCTest
@testable import LocalVoice

final class OverlayStateTests: XCTestCase {
    func testRefiningTitleUsesPromptName() {
        let state = OverlayState.refining(promptName: "Promptify", transcript: "texto")

        XCTAssertEqual(state.displayTitle, "Promptify...")
    }
}
