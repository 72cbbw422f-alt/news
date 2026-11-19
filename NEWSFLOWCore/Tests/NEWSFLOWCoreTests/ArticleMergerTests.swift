import XCTest
@testable import NEWSFLOWCore

final class ArticleMergerTests: XCTestCase {
    func testRefreshUpdatesMetadataButPreservesLocalState() {
        let sourceID = UUID()
        let articleID = UUID()
        let firstSeen = Date(timeIntervalSince1970: 100)
        let old = Article(
            id: articleID,
            sourceID: sourceID,
            externalID: "story-1",
            title: "Old title",
            summary: "Old summary",
            firstSeenAt: firstSeen,
            isRead: true,
            isSaved: true
        )
        let refreshed = Article(
            sourceID: sourceID,
            externalID: "story-1",
            canonicalURL: URL(string: "https://example.com/story-1"),
            title: "Updated title",
            summary: "Updated summary",
            author: "News Desk",
            publishedAt: Date(timeIntervalSince1970: 200)
        )

        let result = ArticleMerger.merge(existing: [old], incoming: [refreshed])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, articleID)
        XCTAssertEqual(result[0].firstSeenAt, firstSeen)
        XCTAssertTrue(result[0].isRead)
        XCTAssertTrue(result[0].isSaved)
        XCTAssertEqual(result[0].title, "Updated title")
        XCTAssertEqual(result[0].summary, "Updated summary")
        XCTAssertEqual(result[0].author, "News Desk")
    }

    func testNewArticlesAreAppendedWithoutChangingExistingOrder() {
        let sourceID = UUID()
        let first = Article(sourceID: sourceID, externalID: "one", title: "One")
        let second = Article(sourceID: sourceID, externalID: "two", title: "Two")
        let third = Article(sourceID: sourceID, externalID: "three", title: "Three")

        let result = ArticleMerger.merge(existing: [first, second], incoming: [third, first])

        XCTAssertEqual(result.map(\.externalID), ["one", "two", "three"])
    }

    func testMissingIncomingMetadataDoesNotEraseStoredMetadata() {
        let sourceID = UUID()
        let old = Article(
            sourceID: sourceID,
            externalID: "story",
            title: "Story",
            summary: "Keep this summary",
            author: "Original author"
        )
        let refreshed = Article(sourceID: sourceID, externalID: "story", title: "Story updated")

        let result = ArticleMerger.merge(existing: [old], incoming: [refreshed])

        XCTAssertEqual(result[0].summary, "Keep this summary")
        XCTAssertEqual(result[0].author, "Original author")
    }
}
