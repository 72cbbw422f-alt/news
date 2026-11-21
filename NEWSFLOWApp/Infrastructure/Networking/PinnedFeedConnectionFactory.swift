import Foundation
import Network
import NEWSFLOWCore

struct PinnedFeedConnectionCandidate {
    let address: FeedIPAddress
    let connection: NWConnection
}

enum PinnedFeedConnectionFactoryError: Error, Equatable {
    case invalidURL
    case httpsRequired
    case invalidHostname
    case unsupportedPort
    case invalidNumericAddress
}

/// Bridges the Core system-DNS policy to the numeric-IP TLS connection
/// factory. This is connection preparation only: callers still own connection
/// racing, state observation, HTTP framing and cancellation of active peers.
struct PinnedFeedConnectionFactory {
    private let resolutionService: FeedAddressResolutionService

    init(resolver: any FeedAddressResolving = AppleSystemFeedAddressResolver()) {
        self.resolutionService = FeedAddressResolutionService(resolver: resolver)
    }

    /// Resolves and validates every candidate returned by the Apple system
    /// resolver, then prepares one TLS connection per validated numeric IP.
    /// No connection is started here and no hostname-based fallback exists.
    func makeTLSConnections(for url: URL) async throws -> [PinnedFeedConnectionCandidate] {
        guard url.user == nil, url.password == nil else {
            throw PinnedFeedConnectionFactoryError.invalidURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw PinnedFeedConnectionFactoryError.httpsRequired
        }
        guard url.port == nil || url.port == 443 else {
            throw PinnedFeedConnectionFactoryError.unsupportedPort
        }
        guard let host = url.host, !host.isEmpty else {
            throw PinnedFeedConnectionFactoryError.invalidURL
        }
        guard let port = UInt16(exactly: url.port ?? 443), port > 0 else {
            throw PinnedFeedConnectionFactoryError.unsupportedPort
        }

        try Task.checkCancellation()

        guard let hostname = DNSHostname(host) else {
            throw PinnedFeedConnectionFactoryError.invalidHostname
        }

        let addresses = try await resolutionService.resolvePublicAddresses(
            for: hostname.value
        )
        try Task.checkCancellation()

        return try addresses.map { address in
            guard let pinnedAddress = PinnedIPAddress(literal: address.literal) else {
                throw PinnedFeedConnectionFactoryError.invalidNumericAddress
            }

            let connection = try PinnedTLSConnectionFactory.makeConnection(
                serverName: hostname.value,
                address: pinnedAddress,
                port: port
            )

            return PinnedFeedConnectionCandidate(
                address: address,
                connection: connection
            )
        }
    }
}
