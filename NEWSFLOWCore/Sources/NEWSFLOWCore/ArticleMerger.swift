import Foundation

/// Merges refreshed feed entries with the local library without losing user state.
public enum ArticleMerger {
    /// Existing articles remain in their current order. New feed entries are appended.
    /// Matching entries retain their local identity, first-seen timestamp and read/save state.
    public static func merge(existing: [Article], incoming: [Article]) -> [Article] {
        var result = existing
        var indexByKey: [String: Int] = [:]

        for (index, article) in result.enumerated() {
            let key = article.deduplicationKey
            if indexByKey[key] == nil {
                indexByKey[key] = index
            }
        }

        for fresh in incoming {
            let key = fresh.deduplicationKey
            guard let index = indexByKey[key] else {
                indexByKey[key] = result.count
                result.append(fresh)
                continue
            }

            var stored = result[index]
            if !fresh.title.isEmpty { stored.title = fresh.title }
            if let summary = fresh.summary, !summary.isEmpty { stored.summary = summary }
            if let author = fresh.author, !author.isEmpty { stored.author = author }
            if let url = fresh.canonicalURL { stored.canonicalURL = url }
            if let date = fresh.publishedAt { stored.publishedAt = date }
            // Deliberately preserve id, sourceID, firstSeenAt, isRead and isSaved.
            result[index] = stored
        }

        return result
    }
}
