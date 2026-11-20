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

    func testRejectsPrivateAndLoopbackIPv4Destinations() {
        let blocked = [
            "http://127.0.0.1/feed.xml",
            "http://10.0.0.8/feed.xml",
            "http://172.16.0.1/feed.xml",
            "http://192.168.1.1/feed.xml",
            "http://169.254.169.254/latest/meta-data/",
            "http://100.64.0.1/feed.xml",
            "http://224.0.0.1/feed.xml"
        ]
        for value in blocked {
            XCTAssertFalse(FeedSource.validatedHTTPURL(URL(string: value)!), "Expected to block \\(value)")
        }
    }

    func testAllowsPublicIPv4AndOrdinaryHTTPSHostnames() {
        XCTAssertTrue(FeedSource.validatedHTTPURL(URL(string: "https://8.8.8.8/feed.xml")!))
        XCTAssertTrue(FeedSource.validatedHTTPURL(URL(string: "https://feeds.example-news.net/rss.xml")!))
    }

    func testRejectsLocalHostnamesAndNonHTTPDestinations() {
        let blocked = [
            "http://localhost/feed.xml",
            "http://printer.local/feed.xml",
            "http://router.internal/feed.xml",
            "file:///etc/passwd",
            "ftp://feeds.example.org/feed.xml"
        ]
        for value in blocked {
            XCTAssertFalse(FeedSource.validatedHTTPURL(URL(string: value)!), "Expected to block \\(value)")
        }
    }

    func testRejectsCredentialAndNonStandardPortURLTricks() {
        XCTAssertFalse(FeedSource.validatedHTTPURL(URL(string: "https://user:pass@feeds.example.org/rss")!))
        XCTAssertFalse(FeedSource.validatedHTTPURL(URL(string: "http://feeds.example.org:8080/rss")!))
    }

    func testRedirectDestinationUsesSameSafetyValidation() {
        XCTAssertFalse(FeedURLSafety.isAllowed(URL(string: "https://127.0.0.1/private")!))
        XCTAssertTrue(FeedURLSafety.isAllowed(URL(string: "https://news.example.org/feed")!))
    }
}
