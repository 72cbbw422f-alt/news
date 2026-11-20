import Network
import XCTest
@testable import NEWSFLOW

final class PinnedTLSConnectionFactoryTests: XCTestCase {
    func testParsesIPv4AndIPv6AddressLiterals() {
        XCTAssertNotNil(PinnedIPAddress(literal: "203.0.113.10"))
        XCTAssertNotNil(PinnedIPAddress(literal: "2001:db8::10"))
    }

    func testRejectsHostnamesAndMalformedAddressLiteralsAsDestinations() {
        XCTAssertNil(PinnedIPAddress(literal: "feeds.example.org"))
        XCTAssertNil(PinnedIPAddress(literal: "999.10.10.10"))
        XCTAssertNil(PinnedIPAddress(literal: "2001:::10"))
    }

    func testFactoryRejectsLocalOrMalformedTLSIdentity() {
        let address = try! XCTUnwrap(PinnedIPAddress(literal: "203.0.113.10"))

        XCTAssertThrowsError(
            try PinnedTLSConnectionFactory.makeConnection(
                serverName: "printer.local",
                address: address,
                port: 443
            )
        ) { error in
            guard case PinnedTLSConnectionFactory.ConfigurationError.invalidServerName = error else {
                return XCTFail("Expected invalidServerName, got \(error)")
            }
        }
    }

    func testFactoryRejectsPortZero() {
        let address = try! XCTUnwrap(PinnedIPAddress(literal: "203.0.113.10"))

        XCTAssertThrowsError(
            try PinnedTLSConnectionFactory.makeConnection(
                serverName: "feeds.example.org",
                address: address,
                port: 0
            )
        ) { error in
            guard case PinnedTLSConnectionFactory.ConfigurationError.invalidPort = error else {
                return XCTFail("Expected invalidPort, got \(error)")
            }
        }
    }

    func testFactoryBuildsConnectionForValidatedDNSIdentityAndNumericEndpoint() throws {
        let address = try XCTUnwrap(PinnedIPAddress(literal: "203.0.113.10"))

        let connection = try PinnedTLSConnectionFactory.makeConnection(
            serverName: "feeds.example.org",
            address: address,
            port: 443
        )

        XCTAssertNotNil(connection)
        // Deliberately do not start the connection: this unit test validates
        // configuration construction only, not peer routing or TLS behavior.
    }
}
