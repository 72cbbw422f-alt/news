import Foundation

public struct FeedRefreshResult: Sendable {
    public let sourceTitle: String?
    public let websiteURL: URL?
    public let articles: [Article]
    public let fetchedAt: Date
    public let duplicateCount: Int
}

/// Coordinates transport and parsing. Persistence is deliberately injected at a
/// higher layer so the core remains independent from SwiftData and the UI.
public struct FeedRefreshService: Sendable {
    private let client: FeedHTTPClient

    public init(client: FeedHTTPClient = FeedHTTPClient()) {
        self.client = client
    }

    public func refresh(source: FeedSource, now: Date = .now) async throws -> FeedRefreshResult {
        guard FeedSource.validatedHTTPURL(source.feedURL) else {
            throw FeedHTTPError.invalidURL
        }

        let data = try await client.fetch(source.feedURL)
        let parsed = try FeedParser.parse(data: data, baseURL: source.feedURL)

        var seen = Set<String>()
        var normalized: [Article] = []
        var duplicates = 0

        for item in parsed.articles {
            let article = Article(
                sourceID: source.id,
                externalID: item.externalID,
                canonicalURL: item.url,
                title: item.title,
                summary: item.summary,
                author: item.author,
                publishedAt: item.publishedAt,
                firstSeenAt: now
            )
            if seen.insert(article.deduplicationKey).inserted {
                normalized.append(article)
            } else {
                duplicates += 1
            }
        }

        return FeedRefreshResult(
            sourceTitle: parsed.title,
            websiteURL: parsed.websiteURL,
            articles: normalized,
            fetchedAt: now,
            duplicateCount: duplicates
        )
    }
}
