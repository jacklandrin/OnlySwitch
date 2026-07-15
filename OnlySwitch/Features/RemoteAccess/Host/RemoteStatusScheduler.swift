import Defines
import Foundation
import RemoteCore
import Switches

actor RemoteStatusScheduler {
    static let maximumSubscriptionsPerSession = 128

    typealias Sink = @Sendable (RemoteControlStatus) async throws -> Void
    typealias FailureHandler = @Sendable () async -> Void

    private struct Subscriber: Sendable {
        var ids: Set<RemoteControlID>
        let sink: Sink
        let onFailure: FailureHandler
    }

    private struct RefreshWork: Sendable {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let provider: RemoteCatalogProvider
    private let interval: Duration
    private let observeNotifications: Bool
    private let sendTimeout: Duration
    private var subscribers: [UUID: Subscriber] = [:]
    private var refreshTasks: [RemoteControlID: Task<Void, Never>] = [:]
    private var refreshWork: [RemoteControlID: RefreshWork] = [:]
    private var notificationTasks: [Task<Void, Never>] = []
    private var latestStatuses: [RemoteControlID: RemoteControlStatus] = [:]
    private var revision: UInt64 = 0

    var activeRefreshCount: Int { refreshTasks.count + refreshWork.count }

    init(
        provider: RemoteCatalogProvider,
        interval: Duration = .seconds(3),
        observeNotifications: Bool = true,
        sendTimeout: Duration = .seconds(2)
    ) {
        self.provider = provider
        self.interval = interval
        self.observeNotifications = observeNotifications
        self.sendTimeout = sendTimeout
    }

    deinit {
        refreshTasks.values.forEach { $0.cancel() }
        refreshWork.values.forEach { $0.task.cancel() }
        notificationTasks.forEach { $0.cancel() }
    }

    func update(
        sessionID: UUID,
        ids: Set<RemoteControlID>,
        sink: @escaping Sink,
        onFailure: @escaping FailureHandler = {}
    ) async throws {
        guard ids.count <= Self.maximumSubscriptionsPerSession else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Too many status subscriptions")
        }
        let catalog = try await provider.catalog()
        let knownIDs = Set(catalog.map(\.id))
        guard ids.isSubset(of: knownIDs) else {
            throw RemoteProtocolError(code: .controlNotFound, message: "Subscription contains an unknown control")
        }

        let previousUnion = subscribedIDs
        subscribers[sessionID] = Subscriber(ids: ids, sink: sink, onFailure: onFailure)
        reconcileTasks()
        let addedToUnion = subscribedIDs.subtracting(previousUnion)
        for id in addedToUnion { await refresh(id) }
        for id in ids.subtracting(addedToUnion) {
            if let status = latestStatuses[id] { await deliver(status, to: [sessionID]) }
        }
    }

    func remove(sessionID: UUID) {
        subscribers[sessionID] = nil
        reconcileTasks()
    }

    func refreshAll() async {
        for id in subscribedIDs { await refresh(id) }
    }

    func refresh(_ id: RemoteControlID) async {
        guard subscribedIDs.contains(id), refreshWork[id] == nil else { return }
        let token = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(id, token: token)
        }
        refreshWork[id] = RefreshWork(token: token, task: task)
        await task.value
    }

    func stop() {
        refreshTasks.values.forEach { $0.cancel() }
        refreshTasks.removeAll()
        refreshWork.values.forEach { $0.task.cancel() }
        refreshWork.removeAll()
        notificationTasks.forEach { $0.cancel() }
        notificationTasks.removeAll()
        latestStatuses.removeAll()
        subscribers.removeAll()
    }

    private var subscribedIDs: Set<RemoteControlID> {
        subscribers.values.reduce(into: []) { $0.formUnion($1.ids) }
    }

    private func startObservingIfNeeded() {
        guard observeNotifications, subscribedIDs.isEmpty == false, notificationTasks.isEmpty else { return }
        notificationTasks = [
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .changeSettings) {
                    guard Task.isCancelled == false else { return }
                    await self?.refreshAll()
                }
            },
            Task { [weak self] in
                for await notification in NotificationCenter.default.notifications(named: .refreshSingleSwitchStatus) {
                    guard Task.isCancelled == false else { return }
                    if let type = notification.object as? SwitchType {
                        await self?.refresh(.init(kind: .builtIn, value: String(type.rawValue)))
                    }
                }
            }
        ]
    }

    private func reconcileTasks() {
        let desired = subscribedIDs
        for id in refreshTasks.keys where desired.contains(id) == false {
            refreshTasks.removeValue(forKey: id)?.cancel()
        }
        for id in refreshWork.keys where desired.contains(id) == false {
            refreshWork.removeValue(forKey: id)?.task.cancel()
            latestStatuses[id] = nil
        }
        if desired.isEmpty {
            notificationTasks.forEach { $0.cancel() }
            notificationTasks.removeAll()
        } else {
            startObservingIfNeeded()
        }
        for id in desired where refreshTasks[id] == nil {
            refreshTasks[id] = Task { [weak self] in
                guard let self else { return }
                while Task.isCancelled == false {
                    do { try await Task.sleep(for: self.interval) } catch { return }
                    await self.refresh(id)
                }
            }
        }
    }

    private func performRefresh(_ id: RemoteControlID, token: UUID) async {
        defer {
            if refreshWork[id]?.token == token { refreshWork[id] = nil }
        }
        revision &+= 1
        let currentRevision = revision
        guard let status = try? await provider.status(id, currentRevision),
              subscribedIDs.contains(id) else { return }
        latestStatuses[id] = status
        let sessionIDs = subscribers.compactMap { $0.value.ids.contains(id) ? $0.key : nil }
        await deliver(status, to: sessionIDs)
    }

    private func deliver(_ status: RemoteControlStatus, to sessionIDs: [UUID]) async {
        let deliveries = sessionIDs.compactMap { id in subscribers[id].map { (id, $0) } }
        let failures = await withTaskGroup(of: UUID?.self, returning: [UUID].self) { group in
            for (id, subscriber) in deliveries {
                group.addTask { [sendTimeout] in
                    do {
                        try await Self.withTimeout(sendTimeout) { try await subscriber.sink(status) }
                        return nil
                    } catch {
                        return id
                    }
                }
            }
            var failed: [UUID] = []
            for await id in group {
                if let id { failed.append(id) }
            }
            return failed
        }
        for id in failures {
            guard let subscriber = subscribers.removeValue(forKey: id) else { continue }
            await subscriber.onFailure()
        }
        if failures.isEmpty == false { reconcileTasks() }
    }

    private static func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw CancellationError()
            }
            guard let value = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return value
        }
    }
}
