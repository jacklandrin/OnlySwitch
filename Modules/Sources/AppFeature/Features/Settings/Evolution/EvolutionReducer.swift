//
//  EvolutionReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import ComposableArchitecture
import Foundation

/// Settings › Evolution: a sidebar of saved Evolutions with an inline editor,
/// and the Gallery on a second tab.
@Reducer
struct EvolutionReducer {
    enum Tab: Equatable, Hashable {
        case mine
        case gallery
    }

    enum PendingSelection: Equatable {
        case item(UUID)
        case new
    }

    struct LoadFailure: Error, Equatable {}

    @ObservableState
    struct State: Equatable {
        var tab: Tab = .mine
        var evolutionList: IdentifiedArrayOf<EvolutionRowReducer.State> = []
        var selectedID: UUID?
        var detail: EvolutionEditorReducer.State?
        /// Set while asking whether to discard unsaved edits.
        var pendingSelection: PendingSelection?
        /// Set while asking to confirm a deletion.
        var pendingDeletion: EvolutionItem?
        var hasLoaded = false
        var showLoadError = false
        var galleryState = EvolutionGalleryReducer.State()
        var preExecution = ""
        var isOnlyAgentAvailable = false
    }

    @CasePathable
    enum Action {
        case task
        case refresh
        case loadList(Result<[EvolutionItem], LoadFailure>)
        case tabChanged(Tab)
        case rowTapped(UUID)
        case newTapped
        case discardChangesConfirmed
        case discardChangesCancelled
        case deleteTapped(UUID)
        case deleteConfirmed
        case deleteCancelled
        case deleteFinished(Result<UUID, LoadFailure>)
        case row(IdentifiedActionOf<EvolutionRowReducer>)
        case detail(EvolutionEditorReducer.Action)
        case galleryAction(EvolutionGalleryReducer.Action)
        case setPreExecution(String)
        case openOnlyAgent
        case dismissLoadError
    }

    @Dependency(\.evolutionListService) var evolutionListService
    @Dependency(\.onlyAgentLauncher) var onlyAgentLauncher

    @Shared(.appStorage("pre-execution"))
    var preExecution: String?

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task, .refresh:
                return refresh(&state)

            case let .loadList(.success(items)):
                state.hasLoaded = true
                state.evolutionList = IdentifiedArray(uniqueElements: items.map(EvolutionRowReducer.State.init))
                reconcileDetail(&state)
                return .none

            case .loadList(.failure):
                state.hasLoaded = true
                state.showLoadError = true
                return .none

            case let .tabChanged(tab):
                state.tab = tab
                return .none

            case let .rowTapped(id):
                guard id != state.selectedID || state.detail?.id != id else { return .none }
                return select(.item(id), in: &state)

            case .newTapped:
                state.tab = .mine
                return select(.new, in: &state)

            case .discardChangesConfirmed:
                guard let pending = state.pendingSelection else { return .none }
                state.pendingSelection = nil
                applySelection(pending, to: &state)
                return .none

            case .discardChangesCancelled:
                state.pendingSelection = nil
                return .none

            case let .deleteTapped(id):
                state.pendingDeletion = state.evolutionList[id: id]?.evolution
                return .none

            case .deleteCancelled:
                state.pendingDeletion = nil
                return .none

            case .deleteConfirmed:
                guard let item = state.pendingDeletion else { return .none }
                state.pendingDeletion = nil
                let service = evolutionListService
                return .run { send in
                    do {
                        try await service.removeItem(item.id)
                        await send(.deleteFinished(.success(item.id)))
                    } catch {
                        await send(.deleteFinished(.failure(LoadFailure())))
                    }
                }

            case let .deleteFinished(.success(id)):
                state.evolutionList.remove(id: id)
                if state.selectedID == id {
                    state.selectedID = nil
                    state.detail = nil
                }
                return .merge(refresh(&state), .send(.galleryAction(.refresh)))

            case .deleteFinished(.failure):
                state.showLoadError = true
                return .none

            case let .detail(.delegate(.saved(item))):
                var item = item
                let isNew = state.detail?.isNew ?? false
                // A new Evolution is shown in the menu right away.
                item.active = isNew || (state.evolutionList[id: item.id]?.evolution.active ?? false)
                state.selectedID = item.id
                state.detail = makeDetail(for: item, carrying: state.detail?.generation, in: state)
                let service = evolutionListService
                let savedID = item.id
                let activate: Effect<Action> = isNew
                    ? .run { _ in await service.setActive(savedID, true) }
                    : .none
                return .merge(activate, refresh(&state), .send(.galleryAction(.refresh)))

            case .detail, .row:
                return .none

            case .galleryAction(.delegate(.installed)):
                return refresh(&state)

            case .galleryAction:
                return .none

            case let .setPreExecution(value):
                state.preExecution = value
                $preExecution.withLock { $0 = value }
                return .none

            case .openOnlyAgent:
                guard state.isOnlyAgentAvailable else { return .none }
                let launcher = onlyAgentLauncher
                return .run { _ in await launcher.open() }

            case .dismissLoadError:
                state.showLoadError = false
                return .none
            }
        }
        .ifLet(\.detail, action: \.detail) {
            EvolutionEditorReducer()
        }
        .forEach(\.evolutionList, action: \.row) {
            EvolutionRowReducer()
        }

        Scope(state: \.galleryState, action: \.galleryAction) {
            EvolutionGalleryReducer()
        }
    }

    private func refresh(_ state: inout State) -> Effect<Action> {
        state.preExecution = preExecution ?? ""
        state.isOnlyAgentAvailable = onlyAgentLauncher.isAvailable()
        let service = evolutionListService
        return .run { send in
            do {
                await send(.loadList(.success(try await service.loadEvolutionList())))
            } catch {
                await send(.loadList(.failure(LoadFailure())))
            }
        }
    }

    private func select(_ selection: PendingSelection, in state: inout State) -> Effect<Action> {
        if state.detail?.isDirty == true {
            state.pendingSelection = selection
        } else {
            applySelection(selection, to: &state)
        }
        return .none
    }

    private func applySelection(_ selection: PendingSelection, to state: inout State) {
        switch selection {
        case let .item(id):
            guard let item = state.evolutionList[id: id]?.evolution else { return }
            state.selectedID = id
            state.detail = makeDetail(for: item, carrying: nil, in: state)
        case .new:
            state.selectedID = nil
            state.detail = EvolutionEditorReducer.State(generationAvailable: state.isOnlyAgentAvailable)
        }
    }

    /// Keeps the editor in step with a freshly loaded list without discarding
    /// unsaved edits or a new Evolution being written.
    private func reconcileDetail(_ state: inout State) {
        if let detail = state.detail, detail.isNew { return }
        if let id = state.selectedID, let item = state.evolutionList[id: id]?.evolution {
            if let detail = state.detail, detail.id == id, detail.isDirty || detail.generation.isGenerating { return }
            state.detail = makeDetail(for: item, carrying: state.detail?.generation, in: state)
            return
        }
        guard let first = state.evolutionList.first?.evolution else {
            state.selectedID = nil
            state.detail = nil
            return
        }
        state.selectedID = first.id
        state.detail = makeDetail(for: first, carrying: nil, in: state)
    }

    private func makeDetail(
        for item: EvolutionItem,
        carrying generation: EvolutionEditorReducer.Generation?,
        in state: State
    ) -> EvolutionEditorReducer.State {
        var detail = EvolutionEditorReducer.State(evolution: item, generationAvailable: state.isOnlyAgentAvailable)
        if let generation, !generation.isGenerating {
            detail.generation.prompt = generation.prompt
            detail.generation.notes = generation.notes
        }
        return detail
    }
}
