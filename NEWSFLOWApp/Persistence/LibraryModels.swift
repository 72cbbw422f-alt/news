import Foundation
import SwiftData
import NEWSFLOWCore

@Model
final class FeedSourceRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var feedURLString: String
    var websiteURLString: String?
    var isEnabled: Bool
    var folderName: String?
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var lastError: String?

    @Relationship(deleteRule: .cascade, inverse: \ArticleRecord.source)
    var articles: [ArticleRecord] = []

    init(
        id: UUID = UUID(),
        title: String,
        feedURLString: String,
        websiteURLString: String? = nil,
        isEnabled: Bool = true,
        folderName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.feedURLString = feedURLString
        self.websiteURLString = websiteURLString
        self.isEnabled = isEnabled
        self.folderName = folderName
    }

    convenience init(domain: FeedSource) {
        self.init(
            id: domain.id,
            title: domain.title,
            feedURLString: domain.feedURL.absoluteString,
            websiteURLString: domain.websiteURL?.absoluteString,
            isEnabled: domain.isEnabled,
            folderName: domain.folderName
        )
    }

    var domain: FeedSource? {
        guard let url = URL(string: feedURLString) else { return nil }
        return FeedSource(
            id: id,
            title: title,
            feedURL: url,
            websiteURL: websiteURLString.flatMap(URL.init(string:)),
            isEnabled: isEnabled,
            folderName: folderName,
            lastAttemptAt: lastAttemptAt,
            lastSuccessAt: lastSuccessAt,
            lastError: lastError
        )
    }
}

@Model
final class ArticleRecord {
    @Attribute(.unique) var id: UUID
    var externalID: String?
    var canonicalURLString: String?
    var title: String
    var summary: String?
    var fullText: String?
    var author: String?
    var publishedAt: Date?
    var firstSeenAt: Date
    var isRead: Bool
    var isSaved: Bool
    var source: FeedSourceRecord?

    init(
        id: UUID = UUID(),
        externalID: String? = nil,
        canonicalURLString: String? = nil,
        title: String,
        summary: String? = nil,
        fullText: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        firstSeenAt: Date = .now,
        isRead: Bool = false,
        isSaved: Bool = false,
        source: FeedSourceRecord? = nil
    ) {
        self.id = id
        self.externalID = externalID
        self.canonicalURLString = canonicalURLString
        self.title = title
        self.summary = summary
        self.fullText = fullText
        self.author = author
        self.publishedAt = publishedAt
        self.firstSeenAt = firstSeenAt
        self.isRead = isRead
        self.isSaved = isSaved
        self.source = source
    }

    convenience init(domain: Article, source: FeedSourceRecord) {
        self.init(
            id: domain.id,
            externalID: domain.externalID,
            canonicalURLString: domain.canonicalURL?.absoluteString,
            title: domain.title,
            summary: domain.summary,
            fullText: domain.fullText,
            author: domain.author,
            publishedAt: domain.publishedAt,
            firstSeenAt: domain.firstSeenAt,
            isRead: domain.isRead,
            isSaved: domain.isSaved,
            source: source
        )
    }

    var domain: Article {
        Article(
            id: id,
            sourceID: source?.id ?? UUID(),
            externalID: externalID,
            canonicalURL: canonicalURLString.flatMap(URL.init(string:)),
            title: title,
            summary: summary,
            fullText: fullText,
            author: author,
            publishedAt: publishedAt,
            firstSeenAt: firstSeenAt,
            isRead: isRead,
            isSaved: isSaved
        )
    }

    func apply(_ article: Article) {
        title = article.title
        externalID = article.externalID
        canonicalURLString = article.canonicalURL?.absoluteString
        summary = article.summary
        author = article.author
        publishedAt = article.publishedAt
        // Read and saved state are intentionally not overwritten by feed refresh.
    }
}
