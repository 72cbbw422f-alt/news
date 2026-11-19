import XCTest
@testable import NEWSFLOWCore

final class FeedParserTests: XCTestCase {
    func testParsesRSSItemsAndRelativeLinks() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>Example News</title><link>https://example.com</link>
          <item><guid>story-1</guid><title>First story</title>
            <description><![CDATA[<p>Summary text</p>]]></description>
            <link>/stories/1</link><pubDate>Tue, 18 Nov 2025 12:00:00 +0000</pubDate>
          </item>
        </channel></rss>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8), baseURL: URL(string: "https://example.com/feed.xml"))
        XCTAssertEqual(feed.title, "Example News")
        XCTAssertEqual(feed.articles.count, 1)
        XCTAssertEqual(feed.articles.first?.title, "First story")
        XCTAssertEqual(feed.articles.first?.url?.absoluteString, "https://example.com/stories/1")
        XCTAssertEqual(feed.articles.first?.externalID, "story-1")
    }

    func testParsesAtomEntry() throws {
        let xml = """
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Journal</title>
          <link href="https://example.org/" rel="alternate"/>
          <entry><id>tag:example.org,2025:1</id><title>Atom story</title>
            <link href="https://example.org/1" rel="alternate"/>
            <updated>2025-11-18T10:30:00Z</updated><summary>Brief</summary>
          </entry>
        </feed>
        """
        let feed = try FeedParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(feed.title, "Atom Journal")
        XCTAssertEqual(feed.articles.first?.title, "Atom story")
        XCTAssertEqual(feed.articles.first?.url?.absoluteString, "https://example.org/1")
    }

    func testRejectsMalformedXML() {
        XCTAssertThrowsError(try FeedParser.parse(data: Data("<rss><channel>".utf8)))
    }

    func testRejectsNonHTTPFeedURL() {
        XCTAssertFalse(FeedSource.validatedHTTPURL(URL(string: "file:///etc/passwd")!))
        XCTAssertTrue(FeedSource.validatedHTTPURL(URL(string: "https://example.com/feed.xml")!))
    }
}
