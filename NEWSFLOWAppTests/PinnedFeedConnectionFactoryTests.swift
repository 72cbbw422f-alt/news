import XCTest
import NEWSFLOWCore
@testable import NEWSFLOW

private struct FixedFeedAddressResolver: FeedAddressResolving {
    let candidates: [String]

    func resolveAddresses(for hostname: DNSHostname) async throws -> [String] {
        candidates
    }
}

final class PinnedFeedConnectionFactoryTests: XCTestCase {
    func testPreparesOneNumericTLSConnectionForEveryValidatedCandidate() async throws {
        let factory = PinnedFeedConnectionFactory(
            resolver: FixedFeedAddressResolver(
                candidates: ["8.8.8.8", "2001:4860:4860::8888"]
            )
        )

        let candidates = try await factory.makeTLSConnections(
            for: XCTUnwrap(URL(string: "https://feeds.example.org/rss.xml"))
        )

        XCTAssertEqual(candidates.map(\.address.literal), [
            "8.8.8.8",
            "2001:4860:4860::8888"
        ])
        XCTAssertEqual(candidates.count, 2)
        // Connections are prepared but deliberately not started. The TLS
        // loopback suite separately verifies SNI, peer IP and trust behavior.
    }

    func testRejectsWholeCandidateSetWhenOneAddressIsPrivate() async {
        let factory = PinnedFeedConnectionFactory(
            resolver: FixedFeedAddressResolver(
                candidates: ["8.8.8.8", "10.0.0.8"]
            )
        )

        do {
            _ = try await factory.makeTLSConnections(
                for: URL(string: "https://feeds.example.org/rss.xml")!
            )
            XCTFail("Expected mixed public/private candidates to be rejected")
        } catch let error as FeedIPAddressPolicy.ValidationError {
            XCTAssertEqual(error, .nonPublicAddress("10.0.0.8"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsHTTPBeforeResolvingOrPreparingTLS() async {
        let factory = PinnedFeedConnectionFactory(
            resolver: FixedFeedAddressResolver(candidates: ["8.8.8.8"])
        )

        do {
            _ = try await factory.makeTLSConnections(
                for: URL(string: "http://feeds.example.org/rss.xml")!
            )
            XCTFail("Expected HTTPS-only TLS factory")
        } catch let error as PinnedFeedConnectionFactoryError {
            XCTAssertEqual(error, .httpsRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsEmbeddedCredentials() async {
        let factory = PinnedFeedConnectionFactory(
            resolver: FixedFeedAddressResolver(candidates: ["8.8.8.8"])
        )

        do {
            _ = try await factory.makeTLSConnections(
                for: URL(string: "https://reader:secret@feeds.example.org/rss.xml")!
            )
            XCTFail("Expected credentials to be rejected")
        } catch let error as PinnedFeedConnectionFactoryError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
