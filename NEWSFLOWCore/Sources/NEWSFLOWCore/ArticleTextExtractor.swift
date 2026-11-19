import Foundation

/// Extracts a readable text approximation from an HTML document without executing
/// scripts or loading remote resources. This is intentionally conservative: the
/// original article remains available when extraction produces too little text.
public enum ArticleTextExtractor {
    public static func extract(from data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else { return nil }

        let preferred = firstCapture(
            pattern: "(?is)<(?:article|main)\\b[^>]*>(.*?)</(?:article|main)\\s*>",
            in: html
        )
        let content = preferred ?? html

        var cleaned = content
        for pattern in [
            "(?is)<(script|style|noscript|svg|iframe|header|footer|nav|aside|form)\\b[^>]*>.*?</\\1\\s*>",
            "(?is)<!--.*?-->",
            "(?is)<br\\s*/?>",
            "(?is)</(p|div|section|article|h[1-6]|li|blockquote|tr)\\s*>"
        ] {
            cleaned = replacing(pattern: pattern, in: cleaned, with: "\\n")
        }

        cleaned = replacing(pattern: "(?is)<[^>]+>", in: cleaned, with: " ")
        cleaned = decodeEntities(in: cleaned)
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let result = lines.joined(separator: "\\n\\n")
        // Avoid treating menus, cookie notices or near-empty pages as article text.
        return result.count >= 240 ? result : nil
    }

    private static func firstCapture(pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private static func replacing(pattern: String, in value: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        return regex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: replacement
        )
    }

    private static func decodeEntities(in value: String) -> String {
        var result = value
        let named = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
            "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…",
            "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“"
        ]
        for (entity, character) in named {
            result = result.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        guard let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") else { return result }
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in matches {
            guard let whole = Range(match.range, in: result),
                  let digits = Range(match.range(at: 1), in: result) else { continue }
            let raw = String(result[digits])
            let scalarValue = raw.lowercased().hasPrefix("x")
                ? UInt32(raw.dropFirst(), radix: 16)
                : UInt32(raw)
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                result.replaceSubrange(whole, with: String(scalar))
            }
        }
        return result
    }
}
