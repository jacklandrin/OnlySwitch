import Foundation
import Network
import Testing
@testable import RemoteCore
@testable import RemoteTransport

struct RemoteConnectionIOTests {
    @Test func concurrentSendsReserveUniqueSequencesBeforeSuspending() async throws {
        let connection = TestRemoteNetworkConnection()
        let io = RemoteConnectionIO(connection: connection)
        let sendCount = 64

        let tasks = (0..<sendCount).map { value in
            Task {
                try await io.send(.plaintext(.ping(UInt64(value))))
            }
        }

        await connection.waitForSendCount(sendCount)
        let frames = try connection.sentContent.map { data in
            var codec = RemoteFrameCodec()
            return try #require(codec.append(data).first)
        }

        #expect(frames.map(\.sequence) == Array(0..<UInt64(sendCount)))

        connection.completeAllSends()
        for task in tasks {
            try await task.value
        }
    }

    @Test func concurrentReceiveIsRejectedWhileFirstReceiveIsSuspended() async throws {
        let connection = TestRemoteNetworkConnection()
        let io = RemoteConnectionIO(connection: connection)
        let first = Task { try await io.receive() }

        await connection.waitForReceiveCount(1)

        await #expect(throws: RemoteConnectionIO.ConnectionError.concurrentReceive) {
            try await io.receive()
        }

        let frame = try RemoteFrameCodec().encode(.plaintext(.ping(7)), sequence: 0)
        connection.completeNextReceive(with: frame)
        #expect(try await first.value == .plaintext(.ping(7)))
        #expect(connection.receiveCount == 1)
    }

    @Test func taskCancellationDoesNotOwnConnectionTeardown() async throws {
        let connection = TestRemoteNetworkConnection()
        let io = RemoteConnectionIO(connection: connection)
        let send = Task { try await io.send(.plaintext(.ping(1))) }

        await connection.waitForSendCount(1)
        send.cancel()
        #expect(connection.cancelCount == 0)

        connection.completeAllSends()
        await #expect(throws: CancellationError.self) {
            try await send.value
        }
        #expect(connection.cancelCount == 0)

        connection.completeSendsImmediately()
        try await io.send(.plaintext(.ping(2)))
        let sequences = try connection.sentContent.map { data in
            var codec = RemoteFrameCodec()
            return try #require(codec.append(data).first?.sequence)
        }
        #expect(sequences == [0, 1])
        #expect(connection.cancelCount == 0)

        await io.cancel()
        #expect(connection.cancelCount == 1)
    }

    @Test func cancellationBeforeSendStillEnqueuesReservedFrameWithoutSequenceGap() async throws {
        let connection = TestRemoteNetworkConnection()
        let io = RemoteConnectionIO(connection: connection)
        let start = TestSendGate()
        let cancelled = Task {
            await start.wait()
            try await io.send(.plaintext(.ping(1)))
        }
        cancelled.cancel()
        await start.open()

        await connection.waitForSendCount(1)
        connection.completeAllSends()
        await #expect(throws: CancellationError.self) { try await cancelled.value }

        connection.completeSendsImmediately()
        try await io.send(.plaintext(.ping(2)))
        let sequences = try connection.sentContent.map { data in
            var codec = RemoteFrameCodec()
            return try #require(codec.append(data).first).sequence
        }
        #expect(sequences == [0, 1])
    }

    @Test func failedSendPreventsASequenceGapOnTheConnection() async throws {
        let connection = TestRemoteNetworkConnection()
        let io = RemoteConnectionIO(connection: connection)
        let first = Task { try await io.send(.plaintext(.ping(1))) }

        await connection.waitForSendCount(1)
        connection.completeAllSends(error: NWError.posix(.ECONNRESET))
        await #expect(throws: NWError.self) {
            try await first.value
        }

        connection.completeSendsImmediately()
        await #expect(throws: RemoteConnectionIO.ConnectionError.closed) {
            try await io.send(.plaintext(.ping(2)))
        }
        #expect(connection.sentContent.count == 1)
    }

    @Test func lateSendFailureAfterWaiterCancellationMarksConnectionTerminal() async throws {
        let connection = TestRemoteNetworkConnection()
        let io = RemoteConnectionIO(connection: connection)
        let first = Task { try await io.send(.plaintext(.ping(1))) }

        await connection.waitForSendCount(1)
        first.cancel()
        await #expect(throws: CancellationError.self) {
            try await first.value
        }
        #expect(connection.cancelCount == 0)

        connection.completeAllSends(error: NWError.posix(.ECONNRESET))
        connection.completeSendsImmediately()
        await #expect(throws: RemoteConnectionIO.ConnectionError.closed) {
            try await io.send(.plaintext(.ping(2)))
        }
        #expect(connection.sentContent.count == 1)
        #expect(connection.cancelCount == 0)
    }
}

private actor TestSendGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard isOpen == false else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private final class TestRemoteNetworkConnection: RemoteNetworkConnection, @unchecked Sendable {
    private struct State {
        var cancelCount = 0
        var sentContent: [Data] = []
        var sendCompletions: [NWConnection.SendCompletion] = []
        var receiveCompletions: [@Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void] = []
        var receiveCount = 0
        var completesSendsImmediately = false
        var sendWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        var receiveWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        var stateUpdateHandler: (@Sendable (NWConnection.State) -> Void)?
    }

    private let lock = NSLock()
    private var state = State()

    var stateUpdateHandler: (@Sendable (NWConnection.State) -> Void)? {
        get { withLock { $0.stateUpdateHandler } }
        set { withLock { $0.stateUpdateHandler = newValue } }
    }

    var cancelCount: Int { withLock { $0.cancelCount } }
    var sentContent: [Data] { withLock { $0.sentContent } }
    var receiveCount: Int { withLock { $0.receiveCount } }

    func start(queue: DispatchQueue) {}

    func send(
        content: Data?,
        contentContext: NWConnection.ContentContext,
        isComplete: Bool,
        completion: NWConnection.SendCompletion
    ) {
        let (waiters, completesImmediately) = withLock { state -> ([CheckedContinuation<Void, Never>], Bool) in
            state.sentContent.append(content ?? Data())
            state.sendCompletions.append(completion)
            return (
                Self.takeSatisfiedWaiters(&state.sendWaiters, count: state.sentContent.count),
                state.completesSendsImmediately
            )
        }
        waiters.forEach { $0.resume() }
        if completesImmediately, case let .contentProcessed(callback) = completion {
            callback(nil)
        }
    }

    func receive(
        minimumIncompleteLength: Int,
        maximumLength: Int,
        completion: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void
    ) {
        let waiters = withLock { state -> [CheckedContinuation<Void, Never>] in
            state.receiveCount += 1
            state.receiveCompletions.append(completion)
            return Self.takeSatisfiedWaiters(&state.receiveWaiters, count: state.receiveCount)
        }
        waiters.forEach { $0.resume() }
    }

    func cancel() {
        withLock { $0.cancelCount += 1 }
    }

    func waitForSendCount(_ count: Int) async {
        if sentContent.count >= count { return }
        await withCheckedContinuation { continuation in
            let shouldResume = withLock { state in
                guard state.sentContent.count < count else { return true }
                state.sendWaiters.append((count, continuation))
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func waitForReceiveCount(_ count: Int) async {
        if receiveCount >= count { return }
        await withCheckedContinuation { continuation in
            let shouldResume = withLock { state in
                guard state.receiveCount < count else { return true }
                state.receiveWaiters.append((count, continuation))
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func completeAllSends(error: NWError? = nil) {
        let completions = withLock { state in
            defer { state.sendCompletions.removeAll() }
            return state.sendCompletions
        }
        for completion in completions {
            if case let .contentProcessed(callback) = completion { callback(error) }
        }
    }

    func completeSendsImmediately() {
        withLock { $0.completesSendsImmediately = true }
    }

    func completeNextReceive(with data: Data) {
        let completion = withLock { $0.receiveCompletions.removeFirst() }
        completion(data, nil, false, nil)
    }

    private func withLock<Result>(_ body: (inout State) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }

    private static func takeSatisfiedWaiters(
        _ waiters: inout [(Int, CheckedContinuation<Void, Never>)],
        count: Int
    ) -> [CheckedContinuation<Void, Never>] {
        let satisfied = waiters.filter { $0.0 <= count }.map(\.1)
        waiters.removeAll { $0.0 <= count }
        return satisfied
    }
}
