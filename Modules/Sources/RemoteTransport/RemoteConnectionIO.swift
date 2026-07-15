import Foundation
import Network
import RemoteCore

public actor RemoteConnectionIO {
    public enum ConnectionError: Swift.Error, Sendable {
        case closed
        case incompleteFrame
        case sequenceExhausted
    }

    private let connection: NWConnection
    private var codec: RemoteFrameCodec
    private var receivedFrames: [RemoteWireFrame] = []
    private var receiveSequence = RemoteWireSequenceValidator()
    private var nextSendSequence: UInt64? = 0

    public init(
        connection: NWConnection,
        maximumPayloadSize: Int = RemoteFrameCodec.protocolMaximumPayloadSize
    ) {
        self.connection = connection
        self.codec = RemoteFrameCodec(maximumPayloadSize: maximumPayloadSize)
    }

    public func start() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                let gate = RemoteContinuationGate(continuation)
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
            connection.cancel()
        }
    }

    public func send(_ packet: RemoteWirePacket) async throws {
        guard let sequence = nextSendSequence else { throw ConnectionError.sequenceExhausted }
        let frame = try codec.encode(packet, sequence: sequence)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                connection.send(content: frame, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                })
            }
        } onCancel: {
            connection.cancel()
        }
        nextSendSequence = sequence == UInt64.max ? nil : sequence + 1
    }

    public func receive() async throws -> RemoteWirePacket {
        while receivedFrames.isEmpty {
            let data = try await receiveChunk()
            receivedFrames.append(contentsOf: try codec.append(data))
        }
        let frame = receivedFrames.removeFirst()
        try receiveSequence.accept(frame.sequence)
        return frame.packet
    }

    public func cancel() {
        connection.cancel()
    }

    private func receiveChunk() async throws -> Data {
        try await withTaskCancellationHandler {
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
        } onCancel: {
            connection.cancel()
        }
    }
}

private final class RemoteContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Swift.Error>?

    init(_ continuation: CheckedContinuation<Void, Swift.Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Void) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Swift.Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Void, Swift.Error>? {
        lock.lock()
        defer { lock.unlock() }
        defer { continuation = nil }
        return continuation
    }
}
