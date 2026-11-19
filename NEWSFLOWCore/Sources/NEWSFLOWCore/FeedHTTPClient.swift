import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FeedHTTPError: Error, Equatable {
    case invalidURL
    case nonHTTPResponse
    case unacceptableStatusCode(Int)
    case responseTooLarge(limit: Int)
}

/// Fetches feed documents with explicit time and memory bounds.
/// The parser only receives data after the transport has enforced the byte limit.
public struct FeedHTTPClient: Sendable {
    private let session: URLSession
    public let maximumResponseBytes: Int
    public let timeout: TimeInterval

    public init(
        session: URLSession = .shared,
        maximumResponseBytes: Int = 5 * 1_024 * 1_024,
        timeout: TimeInterval = 20
    ) {
        self.session = session
        self.maximumResponseBytes = max(1, maximumResponseBytes)
        self.timeout = max(1, timeout)
    }

    public func fetch(_ url: URL) async throws -> Data {
        guard FeedSource.validatedHTTPURL(url) else {
            throw FeedHTTPError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/atom+xml, application/rss+xml, application/xml, text/xml, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("NEWSFLOW/1.0 (+https://github.com/72cbbw422f-alt/news)", forHTTPHeaderField: "User-Agent")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedHTTPError.nonHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FeedHTTPError.unacceptableStatusCode(http.statusCode)
        }
        if http.expectedContentLength > Int64(maximumResponseBytes) {
            throw FeedHTTPError.responseTooLarge(limit: maximumResponseBytes)
        }

        var data = Data()
        data.reserveCapacity(
            http.expectedContentLength > 0
                ? min(Int(http.expectedContentLength), maximumResponseBytes)
                : min(64 * 1_024, maximumResponseBytes)
        )

        for try await byte in bytes {
            guard data.count < maximumResponseBytes else {
                throw FeedHTTPError.responseTooLarge(limit: maximumResponseBytes)
            }
            data.append(byte)
        }

        return data
    }
}
