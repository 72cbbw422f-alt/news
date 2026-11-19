import XCTest
@testable import NEWSFLOWCore

final class ArticleTests: XCTestCase {
    func testExternalIdentifierTakesPriorityForDeduplication() {
        let sourceID = UUID()
        let first = Article(sourceID: sourceID, externalID: "entry-42", title: "First title")
        let updated = Article(sourceID: sourceID, externalID: "entry-42", title: "Updated title")
        XCTAssertEqual(first.deduplicationKey, updated.deduplicationKey)
    }

    func testCanonicalURLIsFallbackIdentity() {
        let sourceID = UUID()
        let first = Article(sourceID: sourceID, canonicalURL: URL(string: "https://example.com/story"), title: "Story")
        let second = Article(sourceID: sourceID, canonicalURL: URL(string: "https://example.com/story"), title: "Different title")
        XCTAssertEqual(first.deduplicationKey, second.deduplicationKey)
    }

    func testTitleIsLastResortIdentity() {
        let article = Article(sourceID: UUID(), title: "  Hello WORLD  ")
        XCTAssertEqual(article.deduplicationKey, "title:hello world")
    }
}
