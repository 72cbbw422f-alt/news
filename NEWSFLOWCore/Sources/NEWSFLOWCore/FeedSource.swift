import Foundation

public struct FeedSource: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var feedURL: URL
    public var websiteURL: URL?
    public var isEnabled: Bool
    public var folderName: String?
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        title: String,
        feedURL: URL,
        websiteURL: URL? = nil,
        isEnabled: Bool = true,
        folderName: String? = nil,
        lastAttemptAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.title = title
        self.feedURL = feedURL
        self.websiteURL = websiteURL
        self.isEnabled = isEnabled
        self.folderName = folderName
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
    }

    public static func validatedHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else { return false }
        return true
    }
}
