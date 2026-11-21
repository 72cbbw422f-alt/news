import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A parsed numeric IP address and conservative public-destination policy.
///
/// This type deliberately does not resolve hostnames. DNS answers must be
/// parsed individually and the complete A/AAAA set must be accepted before
/// any connection is attempted.
public enum FeedIPAddress: Hashable, Sendable {
    case ipv4([UInt8])
    case ipv6([UInt8])

    public init?(_ literal: String) {
        guard !literal.isEmpty, !literal.contains("%") else { return nil }

        var ipv4 = in_addr()
        if literal.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            let bytes = withUnsafeBytes(of: &ipv4) { Array($0.prefix(4)) }
            self = .ipv4(bytes)
            return
        }

        var ipv6 = in6_addr()
        if literal.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0.prefix(16)) }
            self = .ipv6(bytes)
            return
        }

        return nil
    }

    /// True only for ordinary globally routable unicast destinations.
    /// Special-purpose and transition ranges are rejected conservatively.
    public var isPublicUnicast: Bool {
        switch self {
        case .ipv4(let bytes):
            guard bytes.count == 4 else { return false }
            let a = Int(bytes[0]), b = Int(bytes[1]), c = Int(bytes[2])

            if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
            if a == 100 && (64...127).contains(b) { return false }
            if a == 169 && b == 254 { return false }
            if a == 172 && (16...31).contains(b) { return false }
            if a == 192 && b == 0 { return false }
            if a == 192 && b == 2 { return false }
            if a == 192 && b == 31 && c == 196 { return false }
            if a == 192 && b == 52 && c == 193 { return false }
            if a == 192 && b == 88 && c == 99 { return false }
            if a == 192 && b == 168 { return false }
            if a == 192 && b == 175 && c == 48 { return false }
            if a == 198 && (b == 18 || b == 19) { return false }
            if a == 198 && b == 51 && c == 100 { return false }
            if a == 203 && b == 0 && c == 113 { return false }
            return true

        case .ipv6(let bytes):
            guard bytes.count == 16 else { return false }

            // Accept only IPv6 global-unicast space (2000::/3), then remove
            // special-purpose, documentation and transition allocations.
            guard (bytes[0] & 0xE0) == 0x20 else { return false }

            // IETF protocol assignments and special-purpose block 2001::/23.
            if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] <= 0x01 {
                return false
            }
            // Documentation prefix 2001:db8::/32.
            if bytes[0] == 0x20 && bytes[1] == 0x01
                && bytes[2] == 0x0D && bytes[3] == 0xB8 {
                return false
            }
            // Deprecated 6to4 transition prefix 2002::/16.
            if bytes[0] == 0x20 && bytes[1] == 0x02 { return false }
            // Documentation prefix 3fff::/20.
            if bytes[0] == 0x3F && bytes[1] == 0xFF
                && (bytes[2] & 0xF0) == 0x00 {
                return false
            }
            return true
        }
    }
}
