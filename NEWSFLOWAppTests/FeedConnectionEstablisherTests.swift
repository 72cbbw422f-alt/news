import Foundation
import Network
import XCTest
@testable import NEWSFLOW

final class FeedConnectionEstablisherTests: XCTestCase {
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
    let connection: NWConnection? = nil
    private let nextState: FeedConnectionState
    private(set) var startCount = 0
    private(set) var cancelCount = 0

    init(nextState: FeedConnectionState) {
        self.nextState = nextState
    }

    func start(on queue: DispatchQueue) {
        startCount += 1
        queue.async { [weak self] in
            guard let self else { return }
            self.stateHandler?(self.nextState)
        }
    }

    func cancel() {
        cancelCount += 1
    }

    func validateConnectedPeer() throws {
        // These tests terminate before peer validation.
    }
}
