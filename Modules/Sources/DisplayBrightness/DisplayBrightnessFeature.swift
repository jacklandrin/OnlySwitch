import ComposableArchitecture
import Foundation

@Reducer
public struct DisplayBrightnessFeature {
    @ObservableState
    public struct State: Equatable {
        public var snapshot = BrightnessSnapshot()
        public var settings = BrightnessSettings()
        public var persistedSettings = BrightnessSettings()
        public var hosts: Set<UUID> = []
        public var revisions: [UInt32: UInt64] = [:]
        public var pending: [UInt32: UInt64] = [:]
        public var refreshID: UInt64 = 0
        public var settingsRevision: UInt64 = 0
        public var isRefreshing = false
        public var refreshFailed = false
        public var isSavingSettings = false
        public var settingsSaveFailed = false
        public init() {}
    }

    public enum Action: Sendable {
        case appeared(hostID: UUID)
        case disappeared(hostID: UUID)
        case refresh
        case scanCompleted(requestID: UInt64, snapshot: BrightnessSnapshot)
        case scanFailed(requestID: UInt64)
        case snapshotReceived(BrightnessSnapshot)
        case settingsLoaded(BrightnessSettings, revision: UInt64)
        case levelChanged(screenID: UInt32, level: Double)
        case applyCompleted(screenID: UInt32, generation: UInt64, revision: UInt64, level: Double)
        case applyFailed(screenID: UInt32, generation: UInt64, revision: UInt64)
        case settingsChanged(BrightnessSettings)
        case settingsSaved(BrightnessSettings)
        case settingsSaveFailed(BrightnessSettings)
        case resetSoftwareDimming
        case requestKeyboardAccess
    }

    private enum CancelID: Hashable { case observation, refresh }
    private struct ApplyID: Hashable { var screenID: UInt32 }
    @Dependency(\.displayBrightnessClient) private var client
    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared(let hostID):
                let wasEmpty = state.hosts.isEmpty
                state.hosts.insert(hostID)
                guard wasEmpty else { return .none }
                state.refreshID &+= 1
                state.isRefreshing = true
                state.refreshFailed = false
                let refreshID = state.refreshID, settingsRevision = state.settingsRevision
                return .run { [client] send in
                    // Subscribe first so a topology change during the initial scan is not lost.
                    let stream = await client.events()
                    let settings = await client.loadSettings()
                    guard !Task.isCancelled else { return }
                    await send(.settingsLoaded(settings, revision: settingsRevision))
                    do {
                        let snapshot = try await client.scan()
                        try Task.checkCancellation()
                        await send(.scanCompleted(requestID: refreshID, snapshot: snapshot))
                    } catch is CancellationError { return }
                    catch { await send(.scanFailed(requestID: refreshID)) }
                    for await snapshot in stream {
                        guard !Task.isCancelled else { return }
                        await send(.snapshotReceived(snapshot))
                    }
                }.cancellable(id: CancelID.observation, cancelInFlight: true)

            case .disappeared(let hostID):
                state.hosts.remove(hostID)
                guard state.hosts.isEmpty else { return .none }
                state.isRefreshing = false
                return .merge(.cancel(id: CancelID.observation), .cancel(id: CancelID.refresh))

            case .refresh:
                state.refreshID &+= 1
                state.isRefreshing = true
                state.refreshFailed = false
                let refreshID = state.refreshID, settingsRevision = state.settingsRevision
                return .run { [client] send in
                    let settings = await client.loadSettings()
                    await send(.settingsLoaded(settings, revision: settingsRevision))
                    do {
                        let snapshot = try await client.scan()
                        try Task.checkCancellation()
                        await send(.scanCompleted(requestID: refreshID, snapshot: snapshot))
                    } catch is CancellationError { }
                    catch { await send(.scanFailed(requestID: refreshID)) }
                }.cancellable(id: CancelID.refresh, cancelInFlight: true)

            case let .scanCompleted(requestID, snapshot):
                guard requestID == state.refreshID else { return .none }
                state.isRefreshing = false
                state.refreshFailed = false
                return accept(snapshot, state: &state)

            case .scanFailed(let requestID):
                guard requestID == state.refreshID else { return .none }
                state.isRefreshing = false
                state.refreshFailed = true
                return .none

            case .snapshotReceived(let snapshot):
                return accept(snapshot, state: &state)

            case let .settingsLoaded(settings, revision):
                guard revision == state.settingsRevision, !state.isSavingSettings else { return .none }
                state.settings = settings
                state.persistedSettings = settings
                return .none

            case let .levelChanged(screenID, level):
                guard level.isFinite,
                      let index = state.snapshot.displays.firstIndex(where: { $0.id == screenID }),
                      state.snapshot.displays[index].control != .unavailable else { return .none }
                let level = min(1, max(0, level))
                let revision = (state.revisions[screenID] ?? 0) &+ 1
                let generation = state.snapshot.generation
                state.revisions[screenID] = revision
                state.pending[screenID] = revision
                state.snapshot.displays[index].level = level
                state.snapshot.displays[index].error = false
                let request = BrightnessRequest(screenID: screenID, generation: generation, level: level, revision: revision)
                return .run { [client] send in
                    do {
                        try await client.apply(request)
                        try Task.checkCancellation()
                        await send(.applyCompleted(screenID: screenID, generation: generation, revision: revision, level: level))
                    } catch is CancellationError { }
                    catch { await send(.applyFailed(screenID: screenID, generation: generation, revision: revision)) }
                }.cancellable(id: ApplyID(screenID: screenID), cancelInFlight: true)

            case let .applyCompleted(screenID, generation, revision, level):
                guard generation == state.snapshot.generation, state.pending[screenID] == revision,
                      let index = state.snapshot.displays.firstIndex(where: { $0.id == screenID }) else { return .none }
                state.snapshot.displays[index].appliedLevel = level
                state.snapshot.displays[index].error = false
                state.pending[screenID] = nil
                return .none

            case let .applyFailed(screenID, generation, revision):
                guard generation == state.snapshot.generation, state.pending[screenID] == revision,
                      let index = state.snapshot.displays.firstIndex(where: { $0.id == screenID }) else { return .none }
                state.snapshot.displays[index].error = true
                state.pending[screenID] = nil
                return .none

            case .settingsChanged(let settings):
                guard settings != state.settings else { return .none }
                state.settings = settings
                state.settingsRevision &+= 1
                state.settingsSaveFailed = false
                guard !state.isSavingSettings else { return .none }
                state.isSavingSettings = true
                return save(settings)

            case .settingsSaved(let saved):
                state.persistedSettings = saved
                guard state.settings == saved else { return save(state.settings) }
                state.isSavingSettings = false
                return .none

            case .settingsSaveFailed(let failed):
                state.settingsSaveFailed = true
                guard state.settings == failed else { return save(state.settings) }
                state.settings = state.persistedSettings
                state.isSavingSettings = false
                return .none

            case .requestKeyboardAccess:
                return .run { [client] _ in await client.requestKeyboardAccess() }

            case .resetSoftwareDimming:
                return .run { [client] send in
                    await client.resetSoftwareDimming()
                    await send(.refresh)
                }
            }
        }
    }

    private func accept(_ snapshot: BrightnessSnapshot, state: inout State) -> Effect<Action> {
        guard snapshot.generation >= state.snapshot.generation else { return .none }
        let changedTopology = snapshot.generation != state.snapshot.generation
        let removed = Set(state.snapshot.displays.map(\.id)).subtracting(snapshot.displays.map(\.id))
        var cancelled = changedTopology ? Set(state.pending.keys) : removed
        var incoming = snapshot
        if changedTopology {
            state.pending = [:]
            state.revisions = [:]
        } else {
            for index in incoming.displays.indices {
                let id = incoming.displays[index].id
                guard let pending = state.pending[id] else { continue }
                if pending <= incoming.displays[index].supersededUIRevision {
                    state.pending[id] = nil
                    cancelled.insert(id)
                } else if let current = state.snapshot.displays.first(where: { $0.id == id }) {
                    incoming.displays[index].level = current.level
                }
            }
            for id in removed { state.pending[id] = nil; state.revisions[id] = nil }
        }
        state.snapshot = incoming
        return .merge(cancelled.map { .cancel(id: ApplyID(screenID: $0)) })
    }

    private func save(_ settings: BrightnessSettings) -> Effect<Action> {
        .run { [client] send in
            do {
                try await client.saveSettings(settings)
                await send(.settingsSaved(settings))
            } catch { await send(.settingsSaveFailed(settings)) }
        }
    }
}
