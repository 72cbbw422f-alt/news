import Foundation

/// A conservative, ASCII DNS hostname suitable for use as a TLS server name.
///
/// Internationalized names must be supplied in their ASCII-compatible
/// (punycode) form. A trailing root dot and single-label names are rejected
/// deliberately so callers cannot accidentally pass URL fragments, IP
/// literals, or local-network names into the TLS identity layer.
public struct DNSHostname: Hashable, Sendable {
    public let value: String

    public init?(_ value: String) {
        guard !value.isEmpty,
              value.utf8.count <= 253,
              !value.hasSuffix("."),
              !value.contains(":"),
              !value.contains("/"),
              !value.contains("@"),
              !value.contains("%"),
              !value.contains("?"),
              !value.contains("#")
        else {
            return nil
        }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }

        var containsLetter = false
        for label in labels {
            guard !label.isEmpty,
                  label.utf8.count <= 63,
                  let first = label.utf8.first,
                  let last = label.utf8.last,
                  Self.isASCIIAlphaNumeric(first),
                  Self.isASCIIAlphaNumeric(last)
            else {
                return nil
            }

            for byte in label.utf8 {
                guard Self.isASCIIAlphaNumeric(byte) || byte == 45 else {
                    return nil
                }
                if (65...90).contains(byte) || (97...122).contains(byte) {
                    containsLetter = true
                }
            }
        }

        // Prevent legacy numeric host forms from entering the DNS identity
        // path. Literal IP destinations are represented by a separate type.
        guard containsLetter else { return nil }
        self.value = value
    }

    private static func isASCIIAlphaNumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }
}
