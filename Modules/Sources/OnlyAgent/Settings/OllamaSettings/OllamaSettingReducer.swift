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
        case finishFetching(TaskResult<[ProviderModel]>)
        case binding(BindingAction<State>)
    }
    
    @Shared(.ollamaUrl) var ollamaUrl: String
    @Shared(.ollamaModels) var ollamaModels: [OllamaTag]
    @Dependency(\.modelProviderService) var modelProviderService
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
                case .appear:
                    state.host = ollamaUrl
                    state.modelTags = IdentifiedArray(uniqueElements: ollamaModels)
                    return refresh(state: &state)
                    
                case let .finishFetching(.success(providerModels)):
                    $ollamaModels.withLock { $0 = providerModels.ollamaTags }
                    state.modelTags = IdentifiedArray(uniqueElements: ollamaModels)
                    return .none
                    
                case .finishFetching(.failure):
                    return .none
                    
                case .refresh:
                    return refresh(state: &state)
                    
                case .binding(\.host):
                    modelProviderService.setAPIKey(.ollama, "", state.host)
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
                        try await modelProviderService.models(.ollama)
                    }
                )
            )
        }
    }
}
