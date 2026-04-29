import XCTest
@testable import LocalVoice

final class RefineOutputSanitizerTests: XCTestCase {
    func testRemovesStraightWrappingQuotes() {
        XCTAssertEqual(RefineOutputSanitizer.clean("\"Hola mundo\""), "Hola mundo")
    }

    func testRemovesCurlyWrappingQuotes() {
        XCTAssertEqual(RefineOutputSanitizer.clean("“Hola mundo”"), "Hola mundo")
    }

    func testRemovesLatinWrappingQuotes() {
        XCTAssertEqual(RefineOutputSanitizer.clean("«Hola mundo»"), "Hola mundo")
    }

    func testPreservesInternalQuotes() {
        let text = "\"Decile a Ana: \\\"llego a las cinco\\\".\""

        XCTAssertEqual(
            RefineOutputSanitizer.clean(text),
            "Decile a Ana: \\\"llego a las cinco\\\"."
        )
    }

    func testDoesNotRemovePartialQuotes() {
        XCTAssertEqual(RefineOutputSanitizer.clean("\"Hola mundo"), "\"Hola mundo")
        XCTAssertEqual(RefineOutputSanitizer.clean("Hola mundo\""), "Hola mundo\"")
    }

    func testDoesNotRemoveSingleQuotes() {
        XCTAssertEqual(RefineOutputSanitizer.clean("'Hola mundo'"), "'Hola mundo'")
    }
}
