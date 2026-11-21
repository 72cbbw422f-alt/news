import XCTest
@testable import NEWSFLOWCore

final class FeedIPAddressTests: XCTestCase {
    func testParsesIPv4AndIPv6Literals() {
        XCTAssertNotNil(FeedIPAddress("8.8.8.8"))
        XCTAssertNotNil(FeedIPAddress("2001:4860:4860::8888"))
        XCTAssertNil(FeedIPAddress("feeds.example.org"))
        XCTAssertNil(FeedIPAddress("127.1"))
        XCTAssertNil(FeedIPAddress("fe80::1%en0"))
        XCTAssertNil(FeedIPAddress("[2001:4860:4860::8888]"))
    }

    func testAcceptsOrdinaryGlobalUnicastAddresses() {
        for address in [
            "8.8.8.8",
            "1.1.1.1",
            "2001:4860:4860::8888",
            "2606:4700:4700::1111"
        ] {
            XCTAssertTrue(
                tryUnwrap(address).isPublicUnicast,
                "Expected public unicast address: \(address)"
            )
        }
    }

    func testRejectsIPv4SpecialPurposeRanges() {
        let blocked = [
            "0.0.0.1",
            "10.0.0.1",
            "100.64.0.1",
            "127.0.0.1",
            "169.254.169.254",
            "172.16.0.1",
            "192.0.0.1",
            "192.0.2.1",
            "192.31.196.1",
            "192.52.193.1",
            "192.88.99.1",
            "192.168.1.1",
            "192.175.48.1",
            "198.18.0.1",
            "198.51.100.1",
            "203.0.113.1",
            "224.0.0.1",
            "240.0.0.1",
            "255.255.255.255"
        ]

        for address in blocked {
            XCTAssertFalse(
                tryUnwrap(address).isPublicUnicast,
                "Expected special-purpose address to be rejected: \(address)"
            )
        }
    }

    func testRejectsIPv6NonGlobalAndSpecialPurposeRanges() {
        let blocked = [
            "::",
            "::1",
            "::ffff:127.0.0.1",
            "fc00::1",
            "fe80::1",
            "ff02::1",
            "2001::1",
            "2001:db8::1",
            "2002:0808:0808::1",
            "3fff::1",
            "64:ff9b::808:808"
        ]

        for address in blocked {
            XCTAssertFalse(
                tryUnwrap(address).isPublicUnicast,
                "Expected special-purpose address to be rejected: \(address)"
            )
        }
    }

    private func tryUnwrap(
        _ literal: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> FeedIPAddress {
        guard let address = FeedIPAddress(literal) else {
            XCTFail("Expected valid IP literal: \(literal)", file: file, line: line)
            return .ipv4([])
        }
        return address
    }
}
