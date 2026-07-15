import Foundation
import Defines
import RemoteCore
import Switches

actor RemoteStatusScheduler {
    typealias Sink = @Sendable (RemoteControlStatus) async -> Void

    private struct Subscriber: Sendable {
        var ids: Set<RemoteControlID>
        let sink: Sink
    }

    private let provider: RemoteCatalogProvider
    private let interval: Duration
    private let observeNotifications: Bool
    private var subscribers: [UUID: Subscriber] = [:]
    private var refreshTasks: [RemoteControlID: Task<Void, Never>] = [:]
    private var refreshWork: [RemoteControlID: Task<Void, Never>] = [:]
    private var notificationTasks: [Task<Void, Never>] = []
    private var revision: UInt64 = 0

    init(provider: RemoteCatalogProvider, interval: Duration = .seconds(3), observeNotifications: Bool = true) {
        self.provider = provider
        self.interval = interval
        self.observeNotifications = observeNotifications
    }

    deinit {
        refreshTasks.values.forEach { $0.cancel() }
        refreshWork.values.forEach { $0.cancel() }
        notificationTasks.forEach { $0.cancel() }
    }

    func update(sessionID: UUID, ids: Set<RemoteControlID>, sink: @escaping Sink) {
        startObservingIfNeeded()
        subscribers[sessionID] = Subscriber(ids: ids, sink: sink)
        reconcileTasks()
    }

    func remove(sessionID: UUID) {
        subscribers[sessionID] = nil
        reconcileTasks()
    }

    func refreshAll() {
        for id in subscribedIDs { refresh(id) }
    }

    func refresh(_ id: RemoteControlID) {
        guard subscribedIDs.contains(id), refreshWork[id] == nil else { return }
        refreshWork[id] = Task { [weak self] in
            await self?.performRefresh(id)
        }
    }

    func stop() {
        refreshTasks.values.forEach { $0.cancel() }
        refreshTasks.removeAll()
        refreshWork.values.forEach { $0.cancel() }
        refreshWork.removeAll()
        subscribers.removeAll()
    }

    private var subscribedIDs: Set<RemoteControlID> {
        subscribers.values.reduce(into: []) { $0.formUnion($1.ids) }
    }

    private func startObservingIfNeeded() {
        guard observeNotifications, notificationTasks.isEmpty else { return }
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
        for id in desired where refreshTasks[id] == nil {
            refreshTasks[id] = Task { [weak self] in
                guard let self else { return }
                await self.refresh(id)
                while Task.isCancelled == false {
                    do { try await Task.sleep(for: self.interval) } catch { return }
                    await self.refresh(id)
                }
            }
        }
    }

    private func performRefresh(_ id: RemoteControlID) async {
        defer { refreshWork[id] = nil }
        revision &+= 1
        let currentRevision = revision
        guard let status = try? await provider.status(id, currentRevision) else { return }
        let sinks = subscribers.values.filter { $0.ids.contains(id) }.map(\.sink)
        for sink in sinks { await sink(status) }
    }
}
