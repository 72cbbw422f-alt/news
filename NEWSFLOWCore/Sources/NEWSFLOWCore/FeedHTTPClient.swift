import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FeedHTTPError: Error, Equatable {
    case invalidURL
    case nonHTTPResponse
    case unacceptableStatusCode(Int)
    case responseTooLarge(limit: Int)
    case tooManyRedirects
    case unsafeRedirect
}

/// Fetches feed documents while enforcing response, timeout and redirect limits.
public struct FeedHTTPClient: Sendable {
    public let maximumResponseBytes: Int
    public let timeout: TimeInterval
    public let maximumRedirects: Int
    private let sessionConfiguration: FeedURLSessionConfiguration?

    public init(
        maximumResponseBytes: Int = 5 * 1_024 * 1_024,
        timeout: TimeInterval = 20,
        maximumRedirects: Int = 5
    ) {
        self.maximumResponseBytes = max(1, maximumResponseBytes)
        self.timeout = max(1, timeout)
        self.maximumRedirects = max(0, maximumRedirects)
        self.sessionConfiguration = nil
    }

    /// Internal injection point for deterministic transport tests.
    init(
        maximumResponseBytes: Int = 5 * 1_024 * 1_024,
        timeout: TimeInterval = 20,
        maximumRedirects: Int = 5,
        sessionConfiguration: URLSessionConfiguration
    ) {
        self.maximumResponseBytes = max(1, maximumResponseBytes)
        self.timeout = max(1, timeout)
        self.maximumRedirects = max(0, maximumRedirects)
        self.sessionConfiguration = FeedURLSessionConfiguration(sessionConfiguration)
    }

    public func fetch(_ url: URL) async throws -> Data {
        guard FeedSource.validatedHTTPURL(url) else {
            throw FeedHTTPError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "application/atom+xml, application/rss+xml, application/xml, text/xml, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "NEWSFLOW/1.0 (+https://github.com/72cbbw422f-alt/news)",
            forHTTPHeaderField: "User-Agent"
        )

        let loader = BoundedFeedDownload(
            maximumBytes: maximumResponseBytes,
            maximumRedirects: maximumRedirects,
            sessionConfiguration: sessionConfiguration
        )
        return try await loader.download(request)
    }
}

/// URLSessionConfiguration is reference-typed; this immutable wrapper permits
/// safe injection into the Sendable client without exposing mutation.
private final class FeedURLSessionConfiguration: @unchecked Sendable {
    let value: URLSessionConfiguration

    init(_ value: URLSessionConfiguration) {
        self.value = value
    }
}

/// URLSession delegate callbacks arrive on a serial delegate queue. This object
/// accumulates only up to the configured byte limit and resumes once on completion.
private final class BoundedFeedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumBytes: Int
    private let maximumRedirects: Int
    private let sessionConfiguration: FeedURLSessionConfiguration?
    private var redirectCount = 0
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var buffer = Data()

    init(
        maximumBytes: Int,
        maximumRedirects: Int,
        sessionConfiguration: FeedURLSessionConfiguration?
    ) {
        self.maximumBytes = maximumBytes
        self.maximumRedirects = maximumRedirects
        self.sessionConfiguration = sessionConfiguration
    }

    func download(_ request: URLRequest) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            self.continuation = continuation
            let configuration = sessionConfiguration?.value ?? URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = request.timeoutInterval
            configuration.timeoutIntervalForResource = request.timeoutInterval
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(FeedHTTPError.nonHTTPResponse))
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            finish(.failure(FeedHTTPError.unacceptableStatusCode(http.statusCode)))
            return
        }
        if response.expectedContentLength > Int64(maximumBytes) {
            completionHandler(.cancel)
            finish(.failure(FeedHTTPError.responseTooLarge(limit: maximumBytes)))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard buffer.count + data.count <= maximumBytes else {
            dataTask.cancel()
            finish(.failure(FeedHTTPError.responseTooLarge(limit: maximumBytes)))
            return
        }
        buffer.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirectCount += 1
        guard redirectCount <= maximumRedirects else {
            completionHandler(nil)
            finish(.failure(FeedHTTPError.tooManyRedirects))
            return
        }
        guard let destination = request.url, FeedSource.validatedHTTPURL(destination) else {
            completionHandler(nil)
            finish(.failure(FeedHTTPError.unsafeRedirect))
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
        } else {
            finish(.success(buffer))
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let data):
            continuation.resume(returning: data)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        session?.finishTasksAndInvalidate()
    }
}
