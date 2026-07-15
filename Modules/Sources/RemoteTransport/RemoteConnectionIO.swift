import Foundation
import Network
import RemoteCore

protocol RemoteNetworkConnection: AnyObject, Sendable {
    var stateUpdateHandler: (@Sendable (NWConnection.State) -> Void)? { get set }

    func start(queue: DispatchQueue)
    func send(
        content: Data?,
        contentContext: NWConnection.ContentContext,
        isComplete: Bool,
        completion: NWConnection.SendCompletion
    )
    func receive(
        minimumIncompleteLength: Int,
        maximumLength: Int,
        completion: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void
    )
    func cancel()
}

extension NWConnection: RemoteNetworkConnection {}

public actor RemoteConnectionIO {
    public enum ConnectionError: Swift.Error, Sendable {
        case closed
        case concurrentReceive
        case incompleteFrame
        case sequenceExhausted
    }

    private let connection: any RemoteNetworkConnection
    private var codec: RemoteFrameCodec
    private var receivedFrames: [RemoteWireFrame] = []
    private var receiveSequence = RemoteWireSequenceValidator()
    private var nextSendSequence: UInt64? = 0
    private var receiveInProgress = false
    private var pendingReceive: Task<Data, Swift.Error>?
    private var isUsable = true

    public init(
        connection: NWConnection,
        maximumPayloadSize: Int = RemoteFrameCodec.protocolMaximumPayloadSize
    ) {
        self.init(networkConnection: connection, maximumPayloadSize: maximumPayloadSize)
    }

    init(
        connection: any RemoteNetworkConnection,
        maximumPayloadSize: Int = RemoteFrameCodec.protocolMaximumPayloadSize
    ) {
        self.init(networkConnection: connection, maximumPayloadSize: maximumPayloadSize)
    }

    private init(
        networkConnection: any RemoteNetworkConnection,
        maximumPayloadSize: Int
    ) {
        self.connection = networkConnection
        self.codec = RemoteFrameCodec(maximumPayloadSize: maximumPayloadSize)
    }

    public func start() async throws {
        guard isUsable else { throw ConnectionError.closed }
        let gate = RemoteContinuationGate<Void>()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                    guard gate.install(continuation) else { return }
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            gate.resume(returning: ())
                        case let .failed(error):
                            gate.resume(throwing: error)
                        case .cancelled:
                            gate.resume(throwing: CancellationError())
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global(qos: .userInitiated))
                }
            } onCancel: {
                gate.cancel()
            }
        } catch is CancellationError {
            if Task.isCancelled == false { isUsable = false }
            throw CancellationError()
        } catch {
            isUsable = false
            throw error
        }
    }

    public func send(_ packet: RemoteWirePacket) async throws {
        guard isUsable else { throw ConnectionError.closed }
        guard let sequence = nextSendSequence else { throw ConnectionError.sequenceExhausted }
        let frame = try codec.encode(packet, sequence: sequence)
        nextSendSequence = sequence == UInt64.max ? nil : sequence + 1
        let gate = RemoteContinuationGate<Void>()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                    guard gate.install(continuation) else { return }
                    connection.send(
                        content: frame,
                        contentContext: .defaultMessage,
                        isComplete: true,
                        completion: .contentProcessed { error in
                            if let error { gate.resume(throwing: error) }
                            else { gate.resume(returning: ()) }
                        }
                    )
                }
            } onCancel: {
                gate.cancel()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            isUsable = false
            throw error
        }
    }

    public func receive() async throws -> RemoteWirePacket {
        guard isUsable else { throw ConnectionError.closed }
        guard receiveInProgress == false else { throw ConnectionError.concurrentReceive }
        receiveInProgress = true
        defer { receiveInProgress = false }

        while receivedFrames.isEmpty {
            let task: Task<Data, Swift.Error>
            if let pendingReceive {
                task = pendingReceive
            } else {
                task = Task { try await self.receiveChunk() }
                pendingReceive = task
            }

            let data: Data
            do {
                data = try await waitForReceive(task)
            } catch is CancellationError {
                if Task.isCancelled == false {
                    pendingReceive = nil
                    isUsable = false
                }
                throw CancellationError()
            } catch {
                pendingReceive = nil
                isUsable = false
                throw error
            }
            pendingReceive = nil
            receivedFrames.append(contentsOf: try codec.append(data))
        }
        let frame = receivedFrames.removeFirst()
        try receiveSequence.accept(frame.sequence)
        return frame.packet
    }

    public func cancel() {
        isUsable = false
        connection.cancel()
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Swift.Error>) in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: RemoteFrameCodec.headerSize + RemoteFrameCodec.protocolMaximumPayloadSize
            ) { data, _, isComplete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, data.isEmpty == false { continuation.resume(returning: data) }
                else if isComplete { continuation.resume(throwing: ConnectionError.closed) }
                else { continuation.resume(throwing: ConnectionError.incompleteFrame) }
            }
        }
    }

    private func waitForReceive(_ task: Task<Data, Swift.Error>) async throws -> Data {
        let gate = RemoteContinuationGate<Data>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                Task {
                    do { gate.resume(returning: try await task.value) }
                    catch { gate.resume(throwing: error) }
                }
            }
        } onCancel: {
            gate.cancel()
        }
    }
}

private final class RemoteContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Swift.Error>?
    private var cancellationRequested = false
    private var completed = false

    func install(_ continuation: CheckedContinuation<Value, Swift.Error>) -> Bool {
        lock.lock()
        if cancellationRequested {
            completed = true
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Swift.Error) {
        take()?.resume(throwing: error)
    }

    func cancel() {
        lock.lock()
        guard completed == false else {
            lock.unlock()
            return
        }
        guard let continuation else {
            cancellationRequested = true
            lock.unlock()
            return
        }
        completed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: CancellationError())
    }

    private func take() -> CheckedContinuation<Value, Swift.Error>? {
        lock.lock()
        guard completed == false else {
            lock.unlock()
            return nil
        }
        completed = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        return continuation
    }
}
