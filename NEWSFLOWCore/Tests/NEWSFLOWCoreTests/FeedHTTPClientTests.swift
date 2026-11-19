import XCTest
@testable import NEWSFLOWCore

final class FeedHTTPClientTests: XCTestCase {
    func testClientClampsInvalidLimitsToSafeMinimums() {
        let client = FeedHTTPClient(maximumResponseBytes: 0, timeout: 0)
        XCTAssertEqual(client.maximumResponseBytes, 1)
        XCTAssertEqual(client.timeout, 1)
    }

    func testRejectsNonHTTPFeedURLBeforeNetworkAccess() async {
        let client = FeedHTTPClient()
        do {
            _ = try await client.fetch(URL(string: "file:///tmp/feed.xml")!)
            XCTFail("Expected invalid URL error")
        } catch let error as FeedHTTPError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
