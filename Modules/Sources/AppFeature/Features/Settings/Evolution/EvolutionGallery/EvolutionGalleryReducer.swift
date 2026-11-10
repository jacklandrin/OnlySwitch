//
//  EvolutionGalleryReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import ComposableArchitecture
import Foundation

@Reducer
struct EvolutionGalleryReducer {
    @ObservableState
    struct State: Equatable {
        var galleryList: IdentifiedArrayOf<EvolutionGalleryItemReducer.State> = []
        var isLoading = false
        var loadFailed = false
    }

    @CasePathable
    enum Action {
        case refresh
        case loadList(TaskResult<[EvolutionGalleryItem]>)
        case itemAction(IdentifiedActionOf<EvolutionGalleryItemReducer>)
        case delegate(Delegate)
        enum Delegate: Equatable {
            case installed
        }
    }

    @Dependency(\.evolutionGalleryService) var galleryService

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case .refresh:
                    state.isLoading = true
                    state.loadFailed = false
                    return .run { send in
                        return await send(
                            .loadList(
                                TaskResult {
                                    try await galleryService.fetchGalleryList()
                                }
                            )
                        )
                    }

                case let .loadList(.success(items)):
                    state.isLoading = false
                    state.galleryList =
                    IdentifiedArray(
                        uniqueElements: items.compactMap { item in
                            var tempItem = item
                            tempItem.installed = galleryService.checkInstallation(item.evolution.id)
                            return EvolutionGalleryItemReducer.State(item: tempItem)
                        }
                    )
                    return .none

                case .loadList(.failure(_)):
                    state.isLoading = false
                    state.loadFailed = state.galleryList.isEmpty
                    return .none

                case .itemAction(.element(_, action: .delegate(.installed))):
                    return .send(.delegate(.installed))

                case .itemAction:
                    return .none

                case .delegate:
                    return .none
            }
        }
        .forEach(\.galleryList, action: \.itemAction) {
            EvolutionGalleryItemReducer()
        }
    }
}
