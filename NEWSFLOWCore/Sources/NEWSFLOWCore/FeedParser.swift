import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum FeedParserError: Error, Equatable {
    case invalidXML
    case unsupportedOrEmptyFeed
}

public struct ParsedFeed: Sendable {
    public let title: String?
    public let websiteURL: URL?
    public let articles: [ParsedArticle]
}

public struct ParsedArticle: Sendable {
    public let externalID: String?
    public let url: URL?
    public let title: String
    public let summary: String?
    public let author: String?
    public let publishedAt: Date?
}

/// Minimal RSS 2.0 / Atom parser. Network fetching and response-size limits belong
/// in the transport layer; this type only parses already-bounded data.
public enum FeedParser {
    public static func parse(data: Data, baseURL: URL? = nil) throws -> ParsedFeed {
        let delegate = FeedXMLDelegate(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let result = delegate.result else {
            if delegate.result == nil && parser.parserError == nil {
                throw FeedParserError.unsupportedOrEmptyFeed
            }
            throw FeedParserError.invalidXML
        }
        return result
    }
}

private final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    private enum Format { case unknown, rss, atom }
    private let baseURL: URL?
    private var format: Format = .unknown
    private var feedTitle: String?
    private var websiteURL: URL?
    private var articles: [ParsedArticle] = []
    private var current: [String: String] = [:]
    private var currentElement = ""
    private var currentItemDepth = 0
    private var inItem = false
    private var text = ""
    private var linkHref: String?
    private var resultValue: ParsedFeed?

    var result: ParsedFeed? { resultValue }

    init(baseURL: URL?) { self.baseURL = baseURL }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        currentElement = name
        text = ""

        if name == "rss" || name == "rdf:rdf" { format = .rss }
        if name == "feed" { format = .atom }

        if name == "item" || name == "entry" {
            inItem = true
            currentItemDepth += 1
            current = [:]
            linkHref = nil
        }

        if format == .atom && name == "link" {
            let rel = attributeDict["rel"] ?? "alternate"
            if rel == "alternate", let href = attributeDict["href"] {
                if inItem { current["link"] = href } else { websiteURL = resolve(href) }
            }
        }
        if format == .rss && name == "enclosure", let url = attributeDict["url"] {
            current["enclosure"] = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let value = String(data: CDATABlock, encoding: .utf8) { text += value }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !value.isEmpty {
            if inItem {
                switch name {
                case "guid", "id": current["id"] = value
                case "title": current["title"] = value
                case "description", "summary", "content", "content:encoded": current["summary"] = value
                case "author", "name": current["author"] = value
                case "pubdate", "published", "updated", "dc:date": current["date"] = value
                case "link": if current["link"] == nil { current["link"] = value }
                default: break
                }
            } else if name == "title" {
                feedTitle = value
            } else if name == "link", format == .rss {
                websiteURL = resolve(value)
            }
        }

        if name == "item" || name == "entry" {
            let title = current["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty {
                articles.append(ParsedArticle(
                    externalID: current["id"],
                    url: current["link"].flatMap(resolve),
                    title: title,
                    summary: current["summary"],
                    author: current["author"],
                    publishedAt: parseDate(current["date"])
                ))
            }
            current = [:]
            inItem = false
            currentItemDepth = max(0, currentItemDepth - 1)
        }

        text = ""
        currentElement = ""
        if !inItem && (name == "channel" || name == "feed") {
            resultValue = ParsedFeed(title: feedTitle, websiteURL: websiteURL, articles: articles)
        }
    }

    private func resolve(_ raw: String) -> URL? {
        if let url = URL(string: raw), url.scheme != nil { return url }
        return baseURL.flatMap { URL(string: raw, relativeTo: $0)?.absoluteURL }
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm Z",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}
