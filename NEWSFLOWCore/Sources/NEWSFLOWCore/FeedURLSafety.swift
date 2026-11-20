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
              components.password == nil,
              components.port == nil || components.port == 80 || components.port == 443
        else {
            return false
        }

        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty else { return false }

        // IPv6 literals are rejected conservatively until address-range validation
        // and DNS/address pinning can be implemented consistently on all platforms.
        guard !host.contains(":") else { return false }

        if let octets = ipv4Octets(host) {
            return isPublicIPv4(octets)
        }

        // Reject numeric-only and legacy integer/octal/hex IPv4 representations.
        // URL parsers may interpret a 0x-prefixed host as an IPv4 address even
        // though it is not a conventional dotted-decimal literal.
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
        guard !labels.isEmpty, labels.allSatisfy({ label in
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

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var values: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isNumber }),
                  let value = Int(part),
                  (0...255).contains(value),
                  String(value) == part else { return nil }
            values.append(value)
        }
        return values
    }

    private static func isPublicIPv4(_ ip: [Int]) -> Bool {
        let a = ip[0], b = ip[1], c = ip[2]

        // IANA special-purpose, private, loopback, link-local, shared, multicast
        // and reserved ranges are not valid public feed destinations.
        if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        if a == 169 && b == 254 { return false }
        if a == 172 && (16...31).contains(b) { return false }
        if a == 192 && b == 168 { return false }
        if a == 192 && b == 0 && c == 0 { return false }
        if a == 192 && b == 0 && c == 2 { return false }
        if a == 192 && b == 88 && c == 99 { return false }
        if a == 198 && (b == 18 || b == 19) { return false }
        if a == 198 && b == 51 && c == 100 { return false }
        if a == 203 && b == 0 && c == 113 { return false }
        return true
    }
}
