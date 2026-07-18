import Foundation
import RemoteCore

struct RemoteCatalogSnapshot: Equatable, Sendable {
    let revision: UInt64
    let controls: [RemoteControlDescriptor]
}

actor RemoteCatalogMonitor {
    private let provider: RemoteCatalogProvider
    private let pollInterval: Duration
    private let debounceInterval: Duration
    private let observeNotifications: Bool
    private let pollWait: @Sendable (Duration) async throws -> Void
    private let changeStream: AsyncStream<RemoteCatalogSnapshot>
    private let changeContinuation: AsyncStream<RemoteCatalogSnapshot>.Continuation
    private var snapshot: RemoteCatalogSnapshot?
    private var snapshotGeneration: UInt64 = 0
    private var pollingTask: Task<Void, Never>?
    private var notificationTasks: [Task<Void, Never>] = []
    private var debounceTask: Task<Void, Never>?
    private var refreshTask: Task<RemoteCatalogSnapshot?, Error>?
    private var activeRefreshID: UInt64?
    private var refreshGeneration: UInt64 = 0
    private var refreshFollowUpRequested = false
    private var authenticatedSessionCount = 0

    nonisolated var changes: AsyncStream<RemoteCatalogSnapshot> { changeStream }

    init(
        provider: RemoteCatalogProvider,
        pollInterval: Duration = .seconds(15),
        debounceInterval: Duration = .milliseconds(250),
        observeNotifications: Bool = true,
        pollWait: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: RemoteCatalogSnapshot.self,
            bufferingPolicy: .bufferingNewest(16)
        )
        self.provider = provider
        self.pollInterval = pollInterval
        self.debounceInterval = debounceInterval
        self.observeNotifications = observeNotifications
        self.pollWait = pollWait
        self.changeStream = stream
        self.changeContinuation = continuation
    }

    deinit {
        pollingTask?.cancel()
        notificationTasks.forEach { $0.cancel() }
        debounceTask?.cancel()
        changeContinuation.finish()
    }

    func current() async throws -> RemoteCatalogSnapshot {
        if let snapshot { return snapshot }
        let generation = snapshotGeneration
        let controls = try await loadNormalizedCatalog()
        if let snapshot { return snapshot }
        guard snapshotGeneration == generation else { throw CancellationError() }
        let initial = RemoteCatalogSnapshot(revision: 1, controls: controls)
        snapshot = initial
        return initial
    }

    @discardableResult
    func refresh() async throws -> RemoteCatalogSnapshot? {
        try await requestRefresh()
    }

    @discardableResult
    func requestRefresh() async throws -> RemoteCatalogSnapshot? {
        if let refreshTask {
            refreshFollowUpRequested = true
            return try await refreshTask.value
        }

        refreshGeneration &+= 1
        let refreshID = refreshGeneration
        let task = Task { [weak self] () throws -> RemoteCatalogSnapshot? in
            guard let self else { throw CancellationError() }
            return try await self.performRequestedRefreshes(refreshID: refreshID)
        }
        refreshTask = task
        activeRefreshID = refreshID
        return try await task.value
    }

    private func performRequestedRefreshes(refreshID: UInt64) async throws -> RemoteCatalogSnapshot? {
        defer {
            if activeRefreshID == refreshID {
                refreshTask = nil
                activeRefreshID = nil
                refreshFollowUpRequested = false
            }
        }
        try Task.checkCancellation()
        guard snapshot != nil else {
            _ = try await current()
            try Task.checkCancellation()
            guard refreshFollowUpRequested else { return nil }
            refreshFollowUpRequested = false
            return try await loadAndPublishChangedCatalog()
        }
        var controls = try await loadNormalizedCatalog()
        try Task.checkCancellation()
        if refreshFollowUpRequested {
            refreshFollowUpRequested = false
            controls = try await loadNormalizedCatalog()
            try Task.checkCancellation()
        }
        return publishChangedCatalog(controls)
    }

    private func loadAndPublishChangedCatalog() async throws -> RemoteCatalogSnapshot? {
        let controls = try await loadNormalizedCatalog()
        try Task.checkCancellation()
        return publishChangedCatalog(controls)
    }

    private func publishChangedCatalog(
        _ controls: [RemoteControlDescriptor]
    ) -> RemoteCatalogSnapshot? {
        guard let existing = snapshot, controls != existing.controls else { return nil }
        let changed = RemoteCatalogSnapshot(
            revision: existing.revision &+ 1,
            controls: controls
        )
        snapshot = changed
        changeContinuation.yield(changed)
        return changed
    }

    func setAuthenticatedSessionCount(_ count: Int) async {
        authenticatedSessionCount = max(0, count)
        if authenticatedSessionCount == 0 {
            await stopMonitoring()
        } else {
            startMonitoringIfNeeded()
        }
    }

    func stop() async {
        authenticatedSessionCount = 0
        snapshotGeneration &+= 1
        snapshot = nil
        await stopMonitoring()
    }

    private func startMonitoringIfNeeded() {
        guard pollingTask == nil else { return }
        let interval = pollInterval
        let pollWait = pollWait
        pollingTask = Task { [weak self] in
            while Task.isCancelled == false {
                do {
                    try await pollWait(interval)
                    try Task.checkCancellation()
                    _ = try await self?.requestRefresh()
                } catch is CancellationError {
                    return
                } catch {
                    // A later bounded poll or internal notification retries the snapshot.
                }
            }
        }
        guard observeNotifications else { return }
        let names: [Notification.Name] = [
            Notification.Name("changeSettingNotification"),
            UserDefaults.didChangeNotification,
        ]
        notificationTasks = names.map { name in
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    guard Task.isCancelled == false else { return }
                    await self?.scheduleDebouncedRefresh()
                }
            }
        }
    }

    private func stopMonitoring() async {
        let activePollingTask = pollingTask
        activePollingTask?.cancel()
        self.pollingTask = nil
        let activeNotificationTasks = notificationTasks
        activeNotificationTasks.forEach { $0.cancel() }
        notificationTasks.removeAll()
        let activeDebounceTask = debounceTask
        activeDebounceTask?.cancel()
        debounceTask = nil
        let activeRefreshTask = refreshTask
        activeRefreshTask?.cancel()
        refreshTask = nil
        activeRefreshID = nil
        refreshFollowUpRequested = false
        await activePollingTask?.value
        for task in activeNotificationTasks { await task.value }
        await activeDebounceTask?.value
        _ = await activeRefreshTask?.result
    }

    func scheduleDebouncedRefresh() {
        guard authenticatedSessionCount > 0 else { return }
        debounceTask?.cancel()
        let interval = debounceInterval
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
                try Task.checkCancellation()
                _ = try await self?.requestRefresh()
            } catch {
                // Polling remains the bounded fallback for transient catalog failures.
            }
        }
    }

    private func loadNormalizedCatalog() async throws -> [RemoteControlDescriptor] {
        try await provider.catalog().sorted { lhs, rhs in
            if lhs.id.kind.rawValue != rhs.id.kind.rawValue {
                return lhs.id.kind.rawValue < rhs.id.kind.rawValue
            }
            return lhs.id.value < rhs.id.value
        }
    }
}
