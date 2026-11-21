import Foundation

/// Resolves the numeric address candidates returned by the platform resolver.
///
/// The Apple system resolver does not expose a guaranteed complete,
/// authoritative A+AAAA RRset. Implementations must return every numeric
/// candidate they receive, but must not claim that omitted records do not
/// exist. A caller must validate every returned candidate and connect only to
/// a validated numeric endpoint; it must never re-resolve the hostname while
/// connecting.
///
/// Some system resolver APIs are synchronous and cannot be interrupted.
/// Implementations should return cancellation promptly where possible, and
/// callers must check cancellation after resolution before starting a
/// connection. A cancelled result must never be used to initiate a connection.
public protocol FeedAddressResolving: Sendable {
    func resolveAddresses(for hostname: DNSHostname) async throws -> [String]
}

public enum FeedAddressResolutionError: Error, Equatable {
    case invalidHostname
}

/// Resolves a hostname and validates every numeric candidate returned by the
/// configured resolver before exposing destinations to a connection layer.
///
/// This validates the returned candidate set, not the authoritative complete
/// DNS A+AAAA RRset.
public struct FeedAddressResolutionService: Sendable {
    private let resolver: any FeedAddressResolving

    public init(resolver: any FeedAddressResolving) {
        self.resolver = resolver
    }

    public func resolvePublicAddresses(for hostname: String) async throws -> [FeedIPAddress] {
        try Task.checkCancellation()

        guard let dnsHostname = DNSHostname(hostname) else {
            throw FeedAddressResolutionError.invalidHostname
        }

        let candidates = try await resolver.resolveAddresses(for: dnsHostname)
        try Task.checkCancellation()

        return try FeedIPAddressPolicy.validateAnswerSet(candidates)
    }
}
