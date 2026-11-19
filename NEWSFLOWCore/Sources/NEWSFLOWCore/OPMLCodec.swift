import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum OPMLCodecError: Error, Equatable {
    case invalidDocument
}

/// A feed entry from an OPML subscription document.
public struct OPMLSubscription: Hashable, Sendable {
    public var title: String
    public var feedURL: URL
    public var websiteURL: URL?
    public var folderPath: [String]

    public init(title: String, feedURL: URL, websiteURL: URL? = nil, folderPath: [String] = []) {
        self.title = title
        self.feedURL = feedURL
        self.websiteURL = websiteURL
        self.folderPath = folderPath
    }
}

/// Imports and exports the common OPML 2.0 subscription outline format.
public enum OPMLCodec {
    public static func parse(data: Data) throws -> [OPMLSubscription] {
        let delegate = OPMLImportDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.didFindOPMLRoot else {
            throw OPMLCodecError.invalidDocument
        }
        return delegate.subscriptions
    }

    public static func export(_ subscriptions: [OPMLSubscription], title: String = "NEWSFLOW Subscriptions") -> Data {
        var roots: [OPMLFolderNode] = []

        for subscription in subscriptions {
            var siblings = roots
            insert(subscription, path: subscription.folderPath, into: &siblings)
            roots = siblings
        }

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>\(escape(title))</title></head>
          <body>
        """
        for node in roots.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            xml += render(node, depth: 2)
        }
        xml += """
        
          </body>
        </opml>
        """
        return Data(xml.utf8)
    }

    private static func insert(_ subscription: OPMLSubscription, path: [String], into nodes: inout [OPMLFolderNode]) {
        guard let first = path.first else {
            nodes.append(OPMLFolderNode(subscription: subscription))
            return
        }
        let index: Int
        if let existing = nodes.firstIndex(where: { $0.subscription == nil && $0.name == first }) {
            index = existing
        } else {
            nodes.append(OPMLFolderNode(name: first))
            index = nodes.count - 1
        }
        var children = nodes[index].children
        insert(subscription, path: Array(path.dropFirst()), into: &children)
        nodes[index].children = children
    }

    private static func render(_ node: OPMLFolderNode, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        if let subscription = node.subscription {
            let title = escape(subscription.title)
            let feed = escape(subscription.feedURL.absoluteString)
            let website = subscription.websiteURL.map { " htmlUrl=\"\(escape($0.absoluteString))\"" } ?? ""
            return "\n\(indent)<outline type=\"rss\" text=\"\(title)\" title=\"\(title)\" xmlUrl=\"\(feed)\"\(website)/>"
        }
        let label = escape(node.name)
        var result = "\n\(indent)<outline text=\"\(label)\" title=\"\(label)\">"
        for child in node.children.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            result += render(child, depth: depth + 1)
        }
        result += "\n\(indent)</outline>"
        return result
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private struct OPMLFolderNode {
    var name: String
    var subscription: OPMLSubscription?
    var children: [OPMLFolderNode]

    init(name: String) {
        self.name = name
        self.subscription = nil
        self.children = []
    }

    init(subscription: OPMLSubscription) {
        self.name = subscription.title
        self.subscription = subscription
        self.children = []
    }
}

private final class OPMLImportDelegate: NSObject, XMLParserDelegate {
    private var folderStack: [String] = []
    private var outlineStack: [Bool] = []
    private(set) var subscriptions: [OPMLSubscription] = []
    private(set) var didFindOPMLRoot = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let element = elementName.lowercased()
        if element == "opml" { didFindOPMLRoot = true }
        guard element == "outline" else { return }

        let attributes = Dictionary(attributeDict.map { ($0.key.lowercased(), $0.value) },
                                    uniquingKeysWith: { first, _ in first })
        let feedValue = attributes["xmlurl"] ?? attributes["xmlurl".lowercased()]
        if let feedValue, let feedURL = URL(string: feedValue), FeedSource.validatedHTTPURL(feedURL) {
            let title = attributes["title"] ?? attributes["text"] ?? feedURL.host ?? feedValue
            let website = attributes["htmlurl"].flatMap(URL.init(string:))
            subscriptions.append(OPMLSubscription(
                title: title,
                feedURL: feedURL,
                websiteURL: website,
                folderPath: folderStack
            ))
            outlineStack.append(false)
        } else {
            let folder = attributes["title"] ?? attributes["text"] ?? ""
            folderStack.append(folder)
            outlineStack.append(true)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName.lowercased() == "outline", let wasFolder = outlineStack.popLast() else { return }
        if wasFolder, !folderStack.isEmpty { folderStack.removeLast() }
    }
}
