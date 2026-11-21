import Foundation

/// Conservative validation for feed destinations and redirect targets.
///
/// This blocks local names, non-public IPv4 literals, IPv6 literals and URL
/// credential tricks. It does not resolve DNS names or pin resolved addresses;
/// DNS rebinding protection therefore remains a separate transport-hardening task.
public enum FeedURLSafety {
    public static func isAllowed(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let rawHost = components.host,
              !rawHost.isEmpty,
              components.user == nil,
              components.password == nil
        else {
            return false
        }

        let expectedPort = scheme == "https" ? 443 : 80
        guard components.port == nil || components.port == expectedPort else {
            return false
        }

        // Reject root-dot and empty-label forms instead of normalizing them.
        // Single-label names can be expanded through local DNS search domains.
        let host = rawHost.lowercased()
        guard !host.isEmpty,
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              !host.contains(".."),
              host.utf8.count <= 253
        else {
            return false
        }

        // IPv6 literals are rejected conservatively until address-range validation
        // and DNS/address pinning can be implemented consistently on all platforms.
        guard !host.contains(":") else { return false }

        // Use the same IP classifier as the resolver/pinning policy. Keeping
        // literal-host checks in sync prevents a destination accepted here from
        // being rejected (or inconsistently classified) later in the pipeline.
        if let address = FeedIPAddress(host) {
            return address.isPublicUnicast
        }

        // Reject numeric-only and legacy integer/octal/hex IPv4 representations.
        // URL parsers may interpret these as IPv4 destinations even though they
        // are not conventional dotted-decimal literals.
        guard !host.split(separator: ".", omittingEmptySubsequences: false)
            .contains(where: { $0.hasPrefix("0x") }),
              host.rangeOfCharacter(from: CharacterSet.letters) != nil
        else {
            return false
        }

        let blockedNames = [
            "localhost", "local", "internal", "home", "lan", "test", "invalid", "example"
        ]
        guard !blockedNames.contains(host),
              !blockedNames.contains(where: { host.hasSuffix("." + $0) })
        else {
            return false
        }

        // Reject malformed host labels and trailing/empty labels.
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ label in
            !label.isEmpty &&
            label.count <= 63 &&
            label.first != "-" &&
            label.last != "-" &&
            label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else {
            return false
        }

        return true
    }
}
