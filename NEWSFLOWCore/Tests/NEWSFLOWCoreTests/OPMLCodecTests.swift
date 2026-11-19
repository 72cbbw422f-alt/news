import XCTest
@testable import NEWSFLOWCore

final class OPMLCodecTests: XCTestCase {
    func testImportsFeedsAndNestedFolders() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0"><head><title>Subscriptions</title></head><body>
          <outline text="Technology">
            <outline text="Example" title="Example News" type="rss"
              xmlUrl="https://example.com/feed.xml"
              htmlUrl="https://example.com/"/>
          </outline>
          <outline text="World" type="rss" xmlUrl="https://world.example/rss"/>
        </body></opml>
        """
        let subscriptions = try OPMLCodec.parse(data: Data(xml.utf8))

        XCTAssertEqual(subscriptions.count, 2)
        XCTAssertEqual(subscriptions.first?.title, "Example News")
        XCTAssertEqual(subscriptions.first?.folderPath, ["Technology"])
        XCTAssertEqual(subscriptions.first?.websiteURL?.absoluteString, "https://example.com/")
        XCTAssertEqual(subscriptions.last?.folderPath, [])
    }

    func testExportRoundTripsFolderAndSpecialCharacters() throws {
        let subscriptions = [
            OPMLSubscription(
                title: "News & Views",
                feedURL: URL(string: "https://example.com/rss?a=1&b=2")!,
                websiteURL: URL(string: "https://example.com/"),
                folderPath: ["Tech & Science"]
            )
        ]

        let exported = OPMLCodec.export(subscriptions, title: "My Feeds")
        let imported = try OPMLCodec.parse(data: exported)

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].title, "News & Views")
        XCTAssertEqual(imported[0].feedURL.absoluteString, "https://example.com/rss?a=1&b=2")
        XCTAssertEqual(imported[0].folderPath, ["Tech & Science"])
    }

    func testRejectsNonOPMLDocument() {
        XCTAssertThrowsError(try OPMLCodec.parse(data: Data("<rss/>".utf8)))
    }
}
