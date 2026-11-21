import Foundation

/// Resolves every address record for a DNS hostname.
/// Implementations must return the complete A and AAAA answer set and
/// cooperate with Swift task cancellation. Partial results are not safe.
public protocol FeedAddressResolving: Sendable {
    func resolveAddresses(for hostname: DNSHostname) async throws -> [String]
}

public enum FeedAddressResolutionError: Error, Equatable {
    case invalidHostname
}

/// Resolves a hostname and validates the complete answer set before exposing
/// any numeric destination to a connection layer.
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

        let answers = try await resolver.resolveAddresses(for: dnsHostname)
        try Task.checkCancellation()

        return try FeedIPAddressPolicy.validateAnswerSet(answers)
    }
}
