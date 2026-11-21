import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NEWSFLOWCore

#if !canImport(FoundationNetworking)
private final class RedirectingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "news.example.org"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": "http://127.0.0.1/private"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        var redirectedRequest = URLRequest(url: URL(string: "http://127.0.0.1/private")!)
        redirectedRequest.httpMethod = "GET"
        client?.urlProtocol(
            self,
            wasRedirectedTo: redirectedRequest,
            redirectResponse: response
        )
    }

    override func stopLoading() {}
}


private final class RedirectChainURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "chain.example.org"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let nextPath: String
        switch url.path {
        case "/start":
            nextPath = "/hop1"
        case "/hop1":
            nextPath = "/hop2"
        default:
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("feed".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": nextPath]
        ), let destination = URL(string: nextPath, relativeTo: url)?.absoluteURL else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(
            self,
            wasRedirectedTo: URLRequest(url: destination),
            redirectResponse: response
        )
    }

    override func stopLoading() {}
}
#endif

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
            "http://224.0.0.1/feed.xml",
            "http://192.31.196.1/feed.xml",
            "http://192.52.193.1/feed.xml",
            "http://192.175.48.1/feed.xml",
            "http://0x7f000001/feed.xml",
            "http://0x7f.0.0.1/feed.xml",
            "http://0xA9FEA9FE/latest/meta-data/",
            "http://[::1]/feed.xml",
            "http://[::ffff:127.0.0.1]/feed.xml"
        ]
        for value in blocked {
            XCTAssertFalse(FeedSource.validatedHTTPURL(URL(string: value)!), "Expected to block \\(value)")
        }
    }

    func testAllowsPublicIPv4AndOrdinaryHTTPSHostnames() {
        XCTAssertTrue(FeedSource.validatedHTTPURL(URL(string: "https://8.8.8.8/feed.xml")!))
        XCTAssertTrue(FeedSource.validatedHTTPURL(URL(string: "https://1.1.1.1/feed.xml")!))
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
        XCTAssertFalse(FeedSource.validatedHTTPURL(URL(string: "https://feeds.example.org:80/rss")!))
        XCTAssertFalse(FeedSource.validatedHTTPURL(URL(string: "http://feeds.example.org:443/rss")!))
    }

    func testRedirectDestinationUsesSameSafetyValidation() {
        XCTAssertFalse(FeedURLSafety.isAllowed(URL(string: "https://127.0.0.1/private")!))
        XCTAssertTrue(FeedURLSafety.isAllowed(URL(string: "https://news.example.org/feed")!))
    }
    #if !canImport(FoundationNetworking)
    func testActualHTTPRedirectToLoopbackIsRejectedBeforeFollowingIt() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingURLProtocol.self]
        let client = FeedHTTPClient(sessionConfiguration: configuration)

        do {
            _ = try await client.fetch(URL(string: "https://news.example.org/feed.xml")!)
            XCTFail("Expected unsafe redirect error")
        } catch let error as FeedHTTPError {
            XCTAssertEqual(error, .unsafeRedirect)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testActualRedirectChainStopsAtConfiguredMaximum() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectChainURLProtocol.self]
        let client = FeedHTTPClient(maximumRedirects: 1, sessionConfiguration: configuration)

        do {
            _ = try await client.fetch(URL(string: "https://chain.example.org/start")!)
            XCTFail("Expected redirect limit error")
        } catch let error as FeedHTTPError {
            XCTAssertEqual(error, .tooManyRedirects)
        } catch {
            XCTFail("Unexpected error: \\(error)")
        }
    }
    #endif

}
