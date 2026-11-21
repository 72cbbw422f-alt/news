import Foundation
import Network
import NEWSFLOWCore

enum FeedConnectionState: Equatable {
    case preparing
    case waiting
    case ready
    case failed
    case cancelled
}

/// Small seam around Network.framework so the lifecycle coordinator can be
/// tested with deterministic state transitions without opening real sockets.
protocol FeedConnectionControlling: AnyObject {
    var stateHandler: ((FeedConnectionState) -> Void)? { get set }
    var connection: NWConnection? { get }
    func start(on queue: DispatchQueue)
    func cancel()
    func validateConnectedPeer() throws
}

final class NetworkFeedConnectionController: FeedConnectionControlling {
    private let networkConnection: NWConnection
    private let peerValidator: (NWConnection) throws -> FeedIPAddress

    var stateHandler: ((FeedConnectionState) -> Void)? {
        didSet {
            networkConnection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .setup:
                    self.stateHandler?(.preparing)
                case .waiting:
                    self.stateHandler?(.waiting)
                case .ready:
                    self.stateHandler?(.ready)
                case .failed:
                    self.stateHandler?(.failed)
                case .cancelled:
                    self.stateHandler?(.cancelled)
                @unknown default:
                    self.stateHandler?(.failed)
                }
            }
        }
    }

    var connection: NWConnection? { networkConnection }

    init(
        connection: NWConnection,
        peerValidator: @escaping (NWConnection) throws -> FeedIPAddress =
            HostnameFeedConnectionFactory.validatedPeerAddress(from:)
    ) {
        self.networkConnection = connection
        self.peerValidator = peerValidator
    }

    func start(on queue: DispatchQueue) {
        networkConnection.start(queue: queue)
    }

    func cancel() {
        networkConnection.cancel()
    }

    func validateConnectedPeer() throws {
        _ = try peerValidator(networkConnection)
    }
}

enum FeedConnectionEstablishmentError: Error, Equatable {
    case timedOut
    case connectionFailed
    case connectionCancelled
}

/// Owns the connection until it is ready and its actual peer has passed
/// policy. It resolves exactly once across state callbacks, timeout and task
/// cancellation. On failure it always closes the underlying connection.
enum FeedConnectionEstablisher {
    static func establish(
        _ controller: any FeedConnectionControlling,
        timeout: TimeInterval = 15,
        queue: DispatchQueue = DispatchQueue(
            label: "app.newsflow.feed-connection",
            qos: .utility
        )
    ) async throws -> NWConnection {
        let attempt = FeedConnectionAttempt(controller: controller)
        return try await attempt.run(timeout: max(0.1, timeout), queue: queue)
    }
}

private final class FeedConnectionAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private let controller: any FeedConnectionControlling
    private var continuation: CheckedContinuation<NWConnection, Error>?
    private var timeoutWork: DispatchWorkItem?
    private var finished = false
    private var cancellationRequested = false

    init(controller: any FeedConnectionControlling) {
        self.controller = controller
    }

    func run(timeout: TimeInterval, queue: DispatchQueue) async throws -> NWConnection {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancellationRequested {
                    lock.unlock()
                    controller.cancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                lock.unlock()

                controller.stateHandler = { [weak self] state in
                    self?.receive(state)
                }

                let timeoutWork = DispatchWorkItem { [weak self] in
                    self?.finish(.failure(FeedConnectionEstablishmentError.timedOut))
                }
                lock.lock()
                if !finished {
                    self.timeoutWork = timeoutWork
                }
                lock.unlock()

                queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
                controller.start(on: queue)
            }
        } onCancel: {
            cancel()
        }
    }

    private func receive(_ state: FeedConnectionState) {
        switch state {
        case .ready:
            do {
                try controller.validateConnectedPeer()
                guard let connection = controller.connection else {
                    finish(.failure(FeedConnectionEstablishmentError.connectionFailed))
                    return
                }
                finish(.success(connection), cancelConnection: false)
            } catch {
                finish(.failure(error))
            }
        case .failed:
            finish(.failure(FeedConnectionEstablishmentError.connectionFailed))
        case .cancelled:
            finish(.failure(FeedConnectionEstablishmentError.connectionCancelled))
        case .preparing, .waiting:
            break
        }
    }

    private func cancel() {
        lock.lock()
        cancellationRequested = true
        let hasContinuation = continuation != nil
        lock.unlock()

        controller.cancel()
        if hasContinuation {
            finish(.failure(CancellationError()))
        }
    }

    private func finish(
        _ result: Result<NWConnection, Error>,
        cancelConnection: Bool = true
    ) {
        lock.lock()
        guard !finished, let continuation else {
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil
        let timeoutWork = self.timeoutWork
        self.timeoutWork = nil
        lock.unlock()

        timeoutWork?.cancel()
        controller.stateHandler = nil
        if cancelConnection {
            controller.cancel()
        }

        continuation.resume(with: result)
    }
}
