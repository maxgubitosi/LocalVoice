import XCTest
@testable import LocalVoice

final class MLXModelCatalogTests: XCTestCase {
    func testVisibleCatalogExcludesKnownVLMConversions() {
        let visibleIDs = Set(MLXModelCatalog.models.map(\.id))

        XCTAssertFalse(visibleIDs.contains("mlx-community/Qwen3.5-4B-MLX-4bit"))
        XCTAssertFalse(visibleIDs.contains("mlx-community/Qwen3.5-9B-MLX-4bit"))
    }

    func testVisibleCatalogIncludesCuratedTextModels() {
        let visibleIDs = Set(MLXModelCatalog.models.map(\.id))

        XCTAssertTrue(visibleIDs.contains("mlx-community/gemma-4-e2b-it-4bit"))
        XCTAssertTrue(visibleIDs.contains("mlx-community/gemma-4-e4b-it-4bit"))
        XCTAssertTrue(visibleIDs.contains("mlx-community/Qwen3.5-2B-OptiQ-4bit"))
        XCTAssertTrue(visibleIDs.contains("mlx-community/Phi-4-mini-instruct-4bit"))
    }

    func testExperimentalCandidatesAreNotVisibleByDefault() {
        let visibleIDs = Set(MLXModelCatalog.models.map(\.id))
        let experimentalIDs = Set(MLXModelCatalog.experimentalCandidates.map(\.id))

        XCTAssertFalse(experimentalIDs.isEmpty)
        XCTAssertTrue(experimentalIDs.isDisjoint(with: visibleIDs))
    }
}
