import XCTest
@testable import NEWSFLOWCore

private struct StubFeedAddressResolver: FeedAddressResolving {
    let result: Result<[String], StubResolverError>

    func resolveAddresses(for hostname: DNSHostname) async throws -> [String] {
        try result.get()
    }
}

private enum StubResolverError: Error, Equatable {
    case unavailable
}

private actor ResolverStartSignal {
    private var hasStarted = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        hasStarted = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor SuspendedFeedAddressResolver: FeedAddressResolving {
    private let signal: ResolverStartSignal

    init(signal: ResolverStartSignal) {
        self.signal = signal
    }

    func resolveAddresses(for hostname: DNSHostname) async throws -> [String] {
        await signal.markStarted()
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return ["8.8.8.8"]
    }
}

final class FeedAddressResolutionTests: XCTestCase {
    func testResolvesAndReturnsEveryValidatedPublicAddress() async throws {
        let resolver = StubFeedAddressResolver(
            result: .success(["8.8.8.8", "2001:4860:4860::8888"])
        )
        let service = FeedAddressResolutionService(resolver: resolver)

        let addresses = try await service.resolvePublicAddresses(for: "feeds.example.org")

        XCTAssertEqual(addresses, [
            .ipv4([8, 8, 8, 8]),
            .ipv6([0x20, 0x01, 0x48, 0x60, 0x48, 0x60, 0, 0, 0, 0, 0, 0, 0, 0, 0x88, 0x88])
        ])
    }

    func testRejectsInvalidHostnameBeforeReturningAnyDestination() async {
        let resolver = StubFeedAddressResolver(result: .success(["8.8.8.8"]))
        let service = FeedAddressResolutionService(resolver: resolver)

        do {
            _ = try await service.resolvePublicAddresses(for: "printer.local")
            XCTFail("Expected invalid hostname error")
        } catch let error as FeedAddressResolutionError {
            XCTAssertEqual(error, .invalidHostname)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsEntireAnswerSetWhenAnyAddressIsPrivate() async {
        let resolver = StubFeedAddressResolver(
            result: .success(["8.8.8.8", "192.168.1.10"])
        )
        let service = FeedAddressResolutionService(resolver: resolver)

        do {
            _ = try await service.resolvePublicAddresses(for: "feeds.example.org")
            XCTFail("Expected mixed answer set to be rejected")
        } catch let error as FeedIPAddressPolicy.ValidationError {
            XCTAssertEqual(error, .nonPublicAddress("192.168.1.10"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsEmptyAnswerSet() async {
        let resolver = StubFeedAddressResolver(result: .success([]))
        let service = FeedAddressResolutionService(resolver: resolver)

        do {
            _ = try await service.resolvePublicAddresses(for: "feeds.example.org")
            XCTFail("Expected empty answer set to be rejected")
        } catch let error as FeedIPAddressPolicy.ValidationError {
            XCTAssertEqual(error, .emptyAnswerSet)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsMalformedResolverAnswer() async {
        let resolver = StubFeedAddressResolver(
            result: .success(["8.8.8.8", "not-an-ip"])
        )
        let service = FeedAddressResolutionService(resolver: resolver)

        do {
            _ = try await service.resolvePublicAddresses(for: "feeds.example.org")
            XCTFail("Expected malformed answer to be rejected")
        } catch let error as FeedIPAddressPolicy.ValidationError {
            XCTAssertEqual(error, .invalidAddress("not-an-ip"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPropagatesResolverFailureWithoutFallback() async {
        let resolver = StubFeedAddressResolver(result: .failure(.unavailable))
        let service = FeedAddressResolutionService(resolver: resolver)

        do {
            _ = try await service.resolvePublicAddresses(for: "feeds.example.org")
            XCTFail("Expected resolver failure")
        } catch let error as StubResolverError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPropagatesCancellationWhileResolverIsSuspended() async {
        let signal = ResolverStartSignal()
        let resolver = SuspendedFeedAddressResolver(signal: signal)
        let service = FeedAddressResolutionService(resolver: resolver)

        let resolutionTask = Task {
            try await service.resolvePublicAddresses(for: "feeds.example.org")
        }

        await signal.waitUntilStarted()
        resolutionTask.cancel()

        do {
            _ = try await resolutionTask.value
            XCTFail("Expected cancellation to propagate from the resolver")
        } catch is CancellationError {
            // The resolver was already running and its suspended operation observed cancellation.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
