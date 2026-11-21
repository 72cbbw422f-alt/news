import Foundation
import Network
import Security
import NEWSFLOWCore

enum HostnameFeedConnectionFactoryError: Error, Equatable {
    case invalidURL
    case invalidHostname
    case unsupportedScheme
    case unsupportedPort
    case missingRemoteEndpoint
    case unsupportedRemoteEndpoint
}

/// Creates a system-resolved connection using the URL hostname.
///
/// Network.framework retains responsibility for DNS, address selection,
/// Happy Eyeballs and network-path integration. Callers must wait for .ready,
/// validate the effective remote endpoint with validatedPeerAddress, and only
/// then send HTTP request bytes.
enum HostnameFeedConnectionFactory {
    static func makeConnection(for url: URL) throws -> NWConnection {
        guard url.user == nil, url.password == nil,
              let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty
        else {
            throw HostnameFeedConnectionFactoryError.invalidURL
        }

        let isTLS: Bool
        let defaultPort: UInt16
        switch scheme {
        case "https":
            isTLS = true
            defaultPort = 443
        case "http":
            isTLS = false
            defaultPort = 80
        default:
            throw HostnameFeedConnectionFactoryError.unsupportedScheme
        }

        guard url.port == nil || url.port == Int(defaultPort),
              let port = NWEndpoint.Port(rawValue: url.port.map(UInt16.init) ?? defaultPort)
        else {
            throw HostnameFeedConnectionFactoryError.unsupportedPort
        }

        guard let hostname = DNSHostname(host) else {
            throw HostnameFeedConnectionFactoryError.invalidHostname
        }

        let tlsOptions: NWProtocolTLS.Options?
        if isTLS {
            let options = NWProtocolTLS.Options()
            hostname.value.withCString {
                sec_protocol_options_set_tls_server_name(
                    options.securityProtocolOptions,
                    $0
                )
            }
            // Default Network.framework TLS verification remains enabled:
            // no custom verify block, trust override or hostname bypass.
            tlsOptions = options
        } else {
            tlsOptions = nil
        }

        let parameters = NWParameters(
            tls: tlsOptions,
            tcp: NWProtocolTCP.Options()
        )
        let endpoint = NWEndpoint.hostPort(
            host: .name(hostname.value, nil),
            port: port
        )
        return NWConnection(to: endpoint, using: parameters)
    }

    /// Returns only a numeric peer that passes the shared public-unicast
    /// policy. A hostname endpoint or missing path is a hard failure.
    static func validatedPeerAddress(
        from connection: NWConnection
    ) throws -> FeedIPAddress {
        guard let endpoint = connection.currentPath?.remoteEndpoint else {
            throw HostnameFeedConnectionFactoryError.missingRemoteEndpoint
        }
        return try validatedPeerAddress(from: endpoint)
    }

    static func validatedPeerAddress(
        from endpoint: NWEndpoint
    ) throws -> FeedIPAddress {
        guard case .hostPort(let host, _) = endpoint else {
            throw HostnameFeedConnectionFactoryError.unsupportedRemoteEndpoint
        }

        let literal: String
        switch host {
        case .ipv4(let address):
            literal = String(describing: address)
        case .ipv6(let address):
            literal = String(describing: address)
        case .name:
            throw HostnameFeedConnectionFactoryError.unsupportedRemoteEndpoint
        @unknown default:
            throw HostnameFeedConnectionFactoryError.unsupportedRemoteEndpoint
        }

        return try FeedIPAddressPolicy.validateConnectedPeer(literal)
    }
}
