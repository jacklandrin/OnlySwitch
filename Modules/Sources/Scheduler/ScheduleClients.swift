import Dependencies
import Extensions
import Foundation
import RemoteCore

// MARK: - Storage

public enum ScheduleLoadResult: Equatable, Sendable {
    case loaded([Schedule])
    /// The stored value could not be decoded; it is left untouched until the user saves.
    case corrupted
}

/// Persists the schedule list as a JSON array in `UserDefaults`, using the default (lossless) date strategy.
public struct ScheduleStorageClient: Sendable {
    public var load: @Sendable () -> ScheduleLoadResult
    public var save: @Sendable ([Schedule]) throws -> Void

    public init(
        load: @escaping @Sendable () -> ScheduleLoadResult,
        save: @escaping @Sendable ([Schedule]) throws -> Void
    ) {
        self.load = load
        self.save = save
    }

    public static func userDefaults(_ defaults: UserDefaults, key: String = UserDefaults.Key.schedules) -> Self {
        // `UserDefaults` is documented as thread-safe but not declared `Sendable`.
        let defaults = UncheckedSendable(defaults)
        return Self(
            load: {
                guard let value = defaults.value.object(forKey: key) else { return .loaded([]) }
                guard let data = value as? Data,
                      let schedules = try? JSONDecoder().decode([Schedule].self, from: data) else { return .corrupted }
                return .loaded(schedules)
            },
            save: { schedules in
                let data = try JSONEncoder().encode(schedules)
                defaults.value.set(data, forKey: key)
            }
        )
    }
}

extension ScheduleStorageClient: DependencyKey {
    public static let liveValue = Self.userDefaults(.standard)
    public static let testValue = Self(
        load: unimplemented("ScheduleStorageClient.load", placeholder: .loaded([])),
        save: unimplemented("ScheduleStorageClient.save")
    )
}

// MARK: - Executor

/// Lists runnable controls and runs one. The app supplies the live value.
public struct ScheduleExecutorClient: Sendable {
    public var catalog: @MainActor @Sendable () async -> [RemoteControlDescriptor]
    public var run: @MainActor @Sendable (RemoteControlID, ScheduleAction) async -> ScheduleRunOutcome

    public init(
        catalog: @escaping @MainActor @Sendable () async -> [RemoteControlDescriptor],
        run: @escaping @MainActor @Sendable (RemoteControlID, ScheduleAction) async -> ScheduleRunOutcome
    ) {
        self.catalog = catalog
        self.run = run
    }
}

extension ScheduleExecutorClient: DependencyKey {
    /// Inert default; the app overrides it.
    public static let liveValue = Self(catalog: { [] }, run: { _, _ in .failed("Unavailable") })
    public static let testValue = Self(
        catalog: unimplemented("ScheduleExecutorClient.catalog", placeholder: []),
        run: unimplemented("ScheduleExecutorClient.run", placeholder: .failed("Unimplemented"))
    )
}

// MARK: - Notifications

public struct ScheduleNotificationClient: Sendable {
    public var requestAuthorization: @Sendable () async -> Bool
    public var post: @Sendable (_ title: String, _ body: String) async -> Void

    public init(
        requestAuthorization: @escaping @Sendable () async -> Bool,
        post: @escaping @Sendable (_ title: String, _ body: String) async -> Void
    ) {
        self.requestAuthorization = requestAuthorization
        self.post = post
    }
}

extension ScheduleNotificationClient: DependencyKey {
    /// Inert default; the app overrides it.
    public static let liveValue = Self(requestAuthorization: { false }, post: { _, _ in })
    public static let testValue = Self(
        requestAuthorization: unimplemented("ScheduleNotificationClient.requestAuthorization", placeholder: false),
        post: unimplemented("ScheduleNotificationClient.post")
    )
}

// MARK: - System events

public struct ScheduleSystemEventsClient: Sendable {
    /// Wake, clock and time-zone changes.
    public var events: @Sendable () -> AsyncStream<Void>

    public init(events: @escaping @Sendable () -> AsyncStream<Void>) {
        self.events = events
    }
}

extension ScheduleSystemEventsClient: DependencyKey {
    /// Inert default; the app overrides it.
    public static let liveValue = Self(events: { .finished })
    public static let testValue = Self(
        events: unimplemented("ScheduleSystemEventsClient.events", placeholder: .finished)
    )
}

// MARK: - Dependency values

public extension DependencyValues {
    var scheduleStorage: ScheduleStorageClient {
        get { self[ScheduleStorageClient.self] }
        set { self[ScheduleStorageClient.self] = newValue }
    }

    var scheduleExecutor: ScheduleExecutorClient {
        get { self[ScheduleExecutorClient.self] }
        set { self[ScheduleExecutorClient.self] = newValue }
    }

    var scheduleNotifications: ScheduleNotificationClient {
        get { self[ScheduleNotificationClient.self] }
        set { self[ScheduleNotificationClient.self] = newValue }
    }

    var scheduleSystemEvents: ScheduleSystemEventsClient {
        get { self[ScheduleSystemEventsClient.self] }
        set { self[ScheduleSystemEventsClient.self] = newValue }
    }
}
