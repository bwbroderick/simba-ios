import XCTest
@testable import Simba

final class TextChunkerTests: XCTestCase {

    func test_emptyString_returnsSingleEmptyElement() {
        let result = TextChunker.chunk("")
        XCTAssertEqual(result, [""])
    }

    func test_shortText_returnsSingleElementUnchanged() {
        let text = "Hello world."
        let result = TextChunker.chunk(text)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], text)
    }

    func test_multiSentenceLongText_returnsMultipleChunks() {
        let text = "This is the first sentence. This is the second sentence that makes things longer. " +
                   "Here comes the third sentence. And the fourth sentence completes the paragraph."
        let result = TextChunker.chunk(text)
        XCTAssertGreaterThan(result.count, 1)
        XCTAssertFalse(result.contains(where: { $0.isEmpty }))
        // Verify no content is lost (normalize whitespace for comparison since
        // TextChunker trims each chunk, which can alter inter-sentence spacing)
        let normalize: (String) -> String = { s in
            s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        }
        let joinedNormalized = normalize(result.joined(separator: " "))
        let originalNormalized = normalize(text)
        XCTAssertEqual(joinedNormalized, originalNormalized)
    }

    func test_noSentenceBoundaries_returnsSingleChunk() {
        let text = String(repeating: "a", count: 200)
        let result = TextChunker.chunk(text)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], text)
    }
}
