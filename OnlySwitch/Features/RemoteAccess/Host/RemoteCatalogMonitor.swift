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
    private var pollingTask: Task<Void, Never>?
    private var notificationTasks: [Task<Void, Never>] = []
    private var debounceTask: Task<Void, Never>?
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
        let controls = try await loadNormalizedCatalog()
        if let snapshot { return snapshot }
        let initial = RemoteCatalogSnapshot(revision: 1, controls: controls)
        snapshot = initial
        return initial
    }

    @discardableResult
    func refresh() async throws -> RemoteCatalogSnapshot? {
        guard snapshot != nil else {
            _ = try await current()
            return nil
        }
        let controls = try await loadNormalizedCatalog()
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
        await stopMonitoring()
        snapshot = nil
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
                    _ = try await self?.refresh()
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
        notificationTasks.forEach { $0.cancel() }
        notificationTasks.removeAll()
        debounceTask?.cancel()
        debounceTask = nil
        await activePollingTask?.value
    }

    private func scheduleDebouncedRefresh() {
        guard authenticatedSessionCount > 0 else { return }
        debounceTask?.cancel()
        let interval = debounceInterval
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
                try Task.checkCancellation()
                _ = try await self?.refresh()
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
