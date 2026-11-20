import XCTest
@testable import NEWSFLOWCore

final class DNSHostnameTests: XCTestCase {
    func testAcceptsOrdinaryAndPunycodeHostnames() {
        XCTAssertEqual(DNSHostname("feeds.example.org")?.value, "feeds.example.org")
        XCTAssertEqual(DNSHostname("xn--bro-hoa.example")?.value, "xn--bro-hoa.example")
        XCTAssertEqual(DNSHostname("NEWS.Example.org")?.value, "NEWS.Example.org")
    }

    func testRejectsIPLiteralAndLegacyNumericHostForms() {
        let values = [
            "127.0.0.1",
            "8.8.8.8",
            "2130706433",
            "0x7f000001",
            "::1",
            "[2001:db8::1]"
        ]
        for value in values {
            XCTAssertNil(DNSHostname(value), "Expected to reject \(value)")
        }
    }

    func testRejectsMalformedOrLocalStyleNames() {
        let values = [
            "",
            "localhost",
            "printer.local",
            "printer.internal",
            "router.lan",
            "nas.home",
            "service.test",
            "host.invalid",
            "feed.example",
            ".example.org",
            "example.org.",
            "example..org",
            "-bad.example",
            "bad-.example",
            "bad_label.example",
            "bad label.example",
            "münich.example",
            "bad/name.example",
            "bad@example.org",
            "bad?query.example",
            "bad#fragment.example"
        ]
        for value in values {
            XCTAssertNil(DNSHostname(value), "Expected to reject \(value)")
        }
    }

    func testEnforcesDNSLabelAndFullNameLengths() {
        XCTAssertNil(DNSHostname(String(repeating: "a", count: 64) + ".example"))
        let oversized = Array(repeating: String(repeating: "a", count: 63), count: 4).joined(separator: ".")
        XCTAssertNil(DNSHostname(oversized))
    }
}
