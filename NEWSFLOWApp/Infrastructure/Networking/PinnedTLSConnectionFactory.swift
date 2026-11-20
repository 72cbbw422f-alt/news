import Foundation
import Network
import Security

/// Explicit IP destination used by the feed transport TLS spike.
///
/// Construct this only after the complete DNS answer set has been validated.
/// This type parses address literals; it does not perform DNS resolution or
/// decide whether an address is publicly routable.
enum PinnedIPAddress {
    case ipv4(IPv4Address)
    case ipv6(IPv6Address)

    init?(literal: String) {
        if let ipv4 = IPv4Address(literal) {
            self = .ipv4(ipv4)
        } else if let ipv6 = IPv6Address(literal) {
            self = .ipv6(ipv6)
        } else {
            return nil
        }
    }

    var endpointHost: NWEndpoint.Host {
        switch self {
        case .ipv4(let address):
            return .ipv4(address)
        case .ipv6(let address):
            return .ipv6(address)
        }
    }
}

/// Creates a TLS connection to a numeric IP while retaining the original DNS
/// hostname for TLS SNI and certificate hostname verification.
///
/// This is an isolated implementation spike, not the production feed
/// transport. The caller must validate DNS answers before constructing the
/// IP address, start the returned connection, observe its state and cancel it
/// when its owning task is cancelled. No trust override or URLSession fallback
/// is installed here.
enum PinnedTLSConnectionFactory {
    enum ConfigurationError: Error {
        case invalidServerName
        case invalidPort
    }

    static func makeConnection(
        serverName: String,
        address: PinnedIPAddress,
        port: UInt16
    ) throws -> NWConnection {
        guard !serverName.isEmpty,
              serverName.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !serverName.contains("/"),
              !serverName.contains("@"),
              !serverName.contains(":"),
              !serverName.contains("?"),
              !serverName.contains("#"),
              !serverName.contains("%"),
              IPv4Address(serverName) == nil,
              IPv6Address(serverName) == nil
        else {
            throw ConfigurationError.invalidServerName
        }

        guard port > 0, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw ConfigurationError.invalidPort
        }

        let tlsOptions = NWProtocolTLS.Options()
        serverName.withCString {
            sec_protocol_options_set_tls_server_name(
                tlsOptions.securityProtocolOptions,
                $0
            )
        }

        let parameters = NWParameters(
            tls: tlsOptions,
            tcp: NWProtocolTCP.Options()
        )

        // The network endpoint is the validated numeric address. The TLS
        // server name remains the original hostname, not the IP literal.
        return NWConnection(
            to: .hostPort(host: address.endpointHost, port: endpointPort),
            using: parameters
        )
    }
}
