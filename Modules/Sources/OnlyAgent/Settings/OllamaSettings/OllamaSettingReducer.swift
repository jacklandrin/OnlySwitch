//
//  OllamaSettingReducer.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import ComposableArchitecture
import Sharing
import Dependencies

@available(macOS 26.0, *)
@Reducer
public struct OllamaSettingReducer {
    @ObservableState
    public struct State {
        var host: String = "http://localhost:11434"
        var modelTags: IdentifiedArrayOf<OllamaTag> = []
        
        public init() {}
    }
    
    public init() {}
    
    @CasePathable
    public enum Action: BindableAction {
        case appear
        case refresh
        case finishFetching(TaskResult<[OllamaTag]>)
        case binding(BindingAction<State>)
    }
    
    @Shared(.ollamaUrl) var ollamaUrl: String
    @Shared(.ollamaModels) var ollamaModels: [OllamaTag]
    @Dependency(\.ollamaRequestService) var ollamaRequestService: OllamaRequestService
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
                case .appear:
                    state.host = ollamaUrl
                    state.modelTags = IdentifiedArray(uniqueElements: ollamaModels)
                    return refresh(state: &state)
                    
                case let .finishFetching(.success(tags)):
                    $ollamaModels.withLock { $0 = tags }
                    state.modelTags = IdentifiedArray(uniqueElements: tags)
                    return .none
                    
                case .finishFetching(.failure):
                    return .none
                    
                case .refresh:
                    return refresh(state: &state)
                    
                case .binding(\.host):
                    $ollamaUrl.withLock { $0 = state.host }
                    return .none
                    
                case .binding:
                    return .none
            }
        }
    }
    
    private func refresh(state: inout State) -> EffectOf<Self> {
        .run { send in
            await send(
                .finishFetching(
                    TaskResult {
                        try await ollamaRequestService.tags()
                    }
                )
            )
        }
    }
}
