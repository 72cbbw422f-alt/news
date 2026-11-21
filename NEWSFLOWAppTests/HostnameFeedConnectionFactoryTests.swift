import Foundation
import Network
import XCTest
import NEWSFLOWCore
@testable import NEWSFLOW

final class HostnameFeedConnectionFactoryTests: XCTestCase {
    func testCreatesHTTPSConnectionUsingOriginalHostname() throws {
        let url = try XCTUnwrap(URL(string: "https://feeds.example.org/rss.xml"))
        let connection = try HostnameFeedConnectionFactory.makeConnection(for: url)
        XCTAssertEqual(connection.endpoint, .hostPort(
            host: .name("feeds.example.org", nil),
            port: 443
        ))
        // The connection is intentionally not started in this configuration test.
    }

    func testCreatesHTTPConnectionUsingOriginalHostname() throws {
        let url = try XCTUnwrap(URL(string: "http://feeds.example.org/rss.xml"))
        let connection = try HostnameFeedConnectionFactory.makeConnection(for: url)
        XCTAssertEqual(connection.endpoint, .hostPort(
            host: .name("feeds.example.org", nil),
            port: 80
        ))
    }

    func testRejectsUnsafeURLAndPortBeforeCreatingConnection() throws {
        let invalidURLs = [
            "ftp://feeds.example.org/rss",
            "http://user:secret@feeds.example.org/rss",
            "https://printer.local/rss",
            "https://feeds.example.org:8443/rss",
            "https://feeds.example.org:999999/rss"
        ]

        for value in invalidURLs {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertThrowsError(
                try HostnameFeedConnectionFactory.makeConnection(for: url),
                "Expected rejection for \(value)"
            )
        }
    }

    func testAcceptsPublicIPv4AndIPv6RemoteEndpoints() throws {
        let ipv4 = NWEndpoint.hostPort(
            host: .ipv4(try XCTUnwrap(IPv4Address("8.8.8.8"))),
            port: 443
        )
        let ipv6 = NWEndpoint.hostPort(
            host: .ipv6(try XCTUnwrap(IPv6Address("2001:4860:4860::8888"))),
            port: 443
        )

        XCTAssertEqual(
            try HostnameFeedConnectionFactory.validatedPeerAddress(from: ipv4),
            FeedIPAddress("8.8.8.8")
        )
        XCTAssertEqual(
            try HostnameFeedConnectionFactory.validatedPeerAddress(from: ipv6),
            FeedIPAddress("2001:4860:4860::8888")
        )
    }

    func testRejectsPrivateAndHostnameRemoteEndpoints() throws {
        let loopback = NWEndpoint.hostPort(
            host: .ipv4(try XCTUnwrap(IPv4Address("127.0.0.1"))),
            port: 443
        )
        let unresolvedName = NWEndpoint.hostPort(
            host: .name("feeds.example.org", nil),
            port: 443
        )

        XCTAssertThrowsError(
            try HostnameFeedConnectionFactory.validatedPeerAddress(from: loopback)
        )
        XCTAssertThrowsError(
            try HostnameFeedConnectionFactory.validatedPeerAddress(from: unresolvedName)
        )
    }
}
