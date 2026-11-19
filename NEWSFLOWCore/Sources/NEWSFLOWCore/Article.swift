import Foundation

public struct Article: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let sourceID: UUID
    public var externalID: String?
    public var canonicalURL: URL?
    public var title: String
    public var summary: String?
    public var fullText: String?
    public var author: String?
    public var publishedAt: Date?
    public var firstSeenAt: Date
    public var isRead: Bool
    public var isSaved: Bool

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        externalID: String? = nil,
        canonicalURL: URL? = nil,
        title: String,
        summary: String? = nil,
        fullText: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        firstSeenAt: Date = .now,
        isRead: Bool = false,
        isSaved: Bool = false
    ) {
        self.id = id
        self.sourceID = sourceID
        self.externalID = externalID
        self.canonicalURL = canonicalURL
        self.title = title
        self.summary = summary
        self.fullText = fullText
        self.author = author
        self.publishedAt = publishedAt
        self.firstSeenAt = firstSeenAt
        self.isRead = isRead
        self.isSaved = isSaved
    }

    /// Stable identity used for deduplication within a source.
    public var deduplicationKey: String {
        if let externalID, !externalID.isEmpty { return "id:\(externalID)" }
        if let canonicalURL { return "url:\(canonicalURL.absoluteString)" }
        return "title:\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}
