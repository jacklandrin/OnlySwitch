import ComposableArchitecture
import Foundation
import RemoteCore

@Reducer
struct RemoteAphroditeFeature {
    @ObservableState
    struct State: Equatable {
        var selectedMacID: UUID?
        var apps: [AphroditePersonalTool] = []
        var revision: UInt64?
        var selectedAppID: UUID?
        var isLoading = false
        var loadFailed = false

        init(selectedMacID: UUID? = nil) { self.selectedMacID = selectedMacID }

        var selectedApp: AphroditePersonalTool? {
            guard let selectedAppID else { return nil }
            return apps.first { $0.id == selectedAppID }
        }
    }

    enum Action: Equatable {
        case task
        case selectedMacChanged(UUID?)
        case libraryLoaded(UUID, AphroditeRemoteLibrarySnapshot?)
        case libraryLoadFailed(UUID)
        case selectApp(UUID?)
        case libraryChanged(UUID)
    }

    @Dependency(\.remotePersistence) var persistence
    private enum CancelID { case load }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return load(state: &state)
            case let .selectedMacChanged(macID):
                guard state.selectedMacID != macID else { return .none }
                state.selectedMacID = macID
                state.apps = []
                state.revision = nil
                state.selectedAppID = nil
                state.loadFailed = false
                return load(state: &state)
            case let .libraryChanged(macID):
                guard state.selectedMacID == macID else { return .none }
                return load(state: &state)
            case let .libraryLoaded(macID, snapshot):
                guard state.selectedMacID == macID else { return .none }
                state.isLoading = false
                state.loadFailed = false
                state.apps = snapshot?.apps ?? []
                state.revision = snapshot?.revision
                if state.selectedAppID.map({ id in state.apps.contains(where: { $0.id == id }) == false }) == true {
                    state.selectedAppID = nil
                }
                return .none
            case let .libraryLoadFailed(macID):
                guard state.selectedMacID == macID else { return .none }
                state.isLoading = false
                state.loadFailed = true
                return .none
            case let .selectApp(id):
                guard let id else { state.selectedAppID = nil; return .none }
                guard state.apps.contains(where: { $0.id == id }) else { return .none }
                state.selectedAppID = id
                return .none
            }
        }
    }

    private func load(state: inout State) -> Effect<Action> {
        guard let macID = state.selectedMacID else {
            state.isLoading = false
            state.apps = []
            state.revision = nil
            state.selectedAppID = nil
            return .cancel(id: CancelID.load)
        }
        state.isLoading = true
        state.loadFailed = false
        return .run { [persistence] send in
            do { await send(.libraryLoaded(macID, try await persistence.loadAphroditeLibrary(macID))) }
            catch is CancellationError { return }
            catch { await send(.libraryLoadFailed(macID)) }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
