import Darwin
import Foundation
import NEWSFLOWCore

/// Apple system-DNS adapter for feed destination validation.
///
/// Uses the device's configured resolver through getaddrinfo, with separate
/// IPv4 and IPv6 lookups. Every numeric candidate returned by either lookup
/// is passed to Core for validation. This API does not guarantee a complete
/// authoritative A+AAAA RRset.
///
/// getaddrinfo is synchronous and has no per-query cancellation API. The
/// awaiting Swift task is cancelled promptly, while an already-running OS
/// resolver call may continue in the bounded worker queue. The Core service
/// checks cancellation again before exposing candidates, so a cancelled
/// resolution cannot be used to start a connection.
final class AppleSystemFeedAddressResolver: FeedAddressResolving {
    private static let workerQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "app.newsflow.system-dns"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 4
        return queue
    }()

    func resolveAddresses(for hostname: DNSHostname) async throws -> [String] {
        let state = ResolverContinuationState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard state.install(continuation) else { return }

                Self.workerQueue.addOperation {
                    guard !state.isCancelled else { return }

                    let result = Result {
                        try Self.resolveNumericCandidates(hostname: hostname.value)
                    }
                    state.complete(result)
                }
            }
        } onCancel: {
            state.cancel()
        }
    }

    private static func resolveNumericCandidates(hostname: String) throws -> [String] {
        // Separate family-constrained calls avoid relying on a single
        // AF_UNSPEC result to represent both address families. They still do
        // not establish an atomic or authoritative complete RRset.
        let ipv4 = try resolve(hostname: hostname, family: AF_INET)
        let ipv6 = try resolve(hostname: hostname, family: AF_INET6)

        var seen = Set<String>()
        return (ipv4 + ipv6).filter { seen.insert($0).inserted }
    }

    private static func resolve(hostname: String, family: Int32) throws -> [String] {
        var hints = addrinfo()
        hints.ai_family = family
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostname, nil, &hints, &result)

        guard status == 0 else {
            // No record for one family is normal when the other family has
            // usable records. Other resolver errors fail closed.
            if status == EAI_NONAME || status == EAI_NODATA {
                return []
            }

            throw AppleSystemFeedAddressResolverError(
                code: status,
                message: String(cString: gai_strerror(status))
            )
        }

        guard let first = result else { return [] }
        defer { freeaddrinfo(first) }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = first

        while let entry = current?.pointee {
            defer { current = entry.ai_next }

            guard let socketAddress = entry.ai_addr else { continue }

            var hostBuffer = [CChar](repeating: 0, count: 1_025)
            let nameStatus = getnameinfo(
                socketAddress,
                entry.ai_addrlen,
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard nameStatus == 0 else {
                throw AppleSystemFeedAddressResolverError(
                    code: nameStatus,
                    message: String(cString: gai_strerror(nameStatus))
                )
            }

            addresses.append(String(cString: hostBuffer))
        }

        return addresses
    }
}

private struct AppleSystemFeedAddressResolverError: Error, LocalizedError {
    let code: Int32
    let message: String

    var errorDescription: String? {
        "System DNS resolution failed (\(code)): \(message)"
    }
}

/// Thread-safe, one-shot bridge between the cancellation handler and the
/// blocking resolver worker. Cancellation resumes the caller immediately;
/// completion after cancellation is intentionally discarded.
private final class ResolverContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String], Error>?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func install(_ continuation: CheckedContinuation<[String], Error>) -> Bool {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func complete(_ result: Result<[String], Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else { return }
        continuation.resume(with: result)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(throwing: CancellationError())
    }
}
