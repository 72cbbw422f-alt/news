import Foundation
import Network
import XCTest
@testable import NEWSFLOW

final class FeedConnectionEstablisherTests: XCTestCase {
    func testReadyConnectionPassesPeerValidationAndIsReturned() async throws {
        let controller = FakeFeedConnectionController(nextState: .ready)

        let connection = try await FeedConnectionEstablisher.establish(
            controller,
            timeout: 1,
            queue: DispatchQueue(label: "feed.connection.test.ready")
        )

        XCTAssertTrue(connection === controller.connection)
        XCTAssertEqual(controller.validationCount, 1)
        XCTAssertEqual(controller.cancelCount, 0)
    }

    func testReadyConnectionWithRejectedPeerFailsAndIsCancelled() async {
        let controller = FakeFeedConnectionController(
            nextState: .ready,
            validationError: NSError(
                domain: "FeedPeerPolicy",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Peer rejected"]
            )
        )

        do {
            _ = try await FeedConnectionEstablisher.establish(
                controller,
                timeout: 1,
                queue: DispatchQueue(label: "feed.connection.test.peer-rejected")
            )
            XCTFail("Expected peer validation failure")
        } catch {
            XCTAssertEqual((error as NSError).domain, "FeedPeerPolicy")
        }

        XCTAssertEqual(controller.validationCount, 1)
        XCTAssertEqual(controller.cancelCount, 1)
    }

    func testConnectionFailureTerminatesAttemptAndCancelsController() async {
        let controller = FakeFeedConnectionController(nextState: .failed)

        do {
            _ = try await FeedConnectionEstablisher.establish(
                controller,
                timeout: 1,
                queue: DispatchQueue(label: "feed.connection.test.failure")
            )
            XCTFail("Expected connection failure")
        } catch {
            XCTAssertEqual(
                error as? FeedConnectionEstablishmentError,
                .connectionFailed
            )
        }

        XCTAssertEqual(controller.startCount, 1)
        XCTAssertEqual(controller.cancelCount, 1)
    }

    func testWaitingConnectionTimesOutAndIsCancelled() async {
        let controller = FakeFeedConnectionController(nextState: .waiting)

        do {
            _ = try await FeedConnectionEstablisher.establish(
                controller,
                timeout: 0.02,
                queue: DispatchQueue(label: "feed.connection.test.timeout")
            )
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(
                error as? FeedConnectionEstablishmentError,
                .timedOut
            )
        }

        XCTAssertEqual(controller.startCount, 1)
        XCTAssertEqual(controller.cancelCount, 1)
    }

    func testTaskCancellationCancelsActiveAttempt() async {
        let controller = FakeFeedConnectionController(nextState: .waiting)
        let task = Task {
            try await FeedConnectionEstablisher.establish(
                controller,
                timeout: 5,
                queue: DispatchQueue(label: "feed.connection.test.cancel")
            )
        }

        // The fake signals that start has occurred before the task is cancelled.
        while controller.startCount == 0 {
            await Task.yield()
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \\(error)")
        }

        XCTAssertEqual(controller.cancelCount, 1)
    }
}

private final class FakeFeedConnectionController: FeedConnectionControlling {
    var stateHandler: ((FeedConnectionState) -> Void)?
    let connection: NWConnection
    private let nextState: FeedConnectionState
    private let validationError: Error?
    private let lock = NSLock()
    private var starts = 0
    private var cancels = 0
    private var validations = 0

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancels
    }

    var validationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return validations
    }

    init(nextState: FeedConnectionState, validationError: Error? = nil) {
        self.nextState = nextState
        self.validationError = validationError
        self.connection = NWConnection(
            to: .hostPort(host: .name("example.com", nil), port: 443),
            using: .tcp
        )
    }

    func start(on queue: DispatchQueue) {
        lock.lock()
        starts += 1
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            self.stateHandler?(self.nextState)
        }
    }

    func cancel() {
        lock.lock()
        cancels += 1
        lock.unlock()
    }

    func validateConnectedPeer() throws {
        lock.lock()
        validations += 1
        lock.unlock()
        if let validationError {
            throw validationError
        }
    }
}
