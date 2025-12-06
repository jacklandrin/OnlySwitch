//
//  OpenAISettingReducer.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
public struct OpenAISettingReducer {
    @ObservableState
    public struct State: Equatable {
        public var apiKey: String = ""
        public var host: String = "api.openai.com"
        public var models: [String] = []
        public var verified: Bool? = nil
        
        public init() {}
    }
    
    public init() {}
    
    @CasePathable
    public enum Action: BindableAction {
        case appear
        case check
        case verify(TaskResult<Bool>)
        case binding(BindingAction<State>)
    }
    
    @Dependency(\.openAIService) var openAIService
    @Shared(.openAIAPIKey) var apiKey: String = ""
    @Shared(.openAIHost) var host
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
                case .appear:
                    state.models = openAIService.models().map(\.model)
                    state.apiKey = apiKey
                    state.host = host
                    return .none
            
                case .check:
                    openAIService.setAPIToken(state.apiKey, state.host)
                    $apiKey.withLock { $0 = state.apiKey }
                    $host.withLock { $0 = state.host }
                    return .run { send in
                       await send(
                            .verify(
                                TaskResult {
                                    await openAIService.test()
                                }
                            )
                        )
                    }
                    
                case let .verify(.success(result)):
                    state.verified = result
                    return .none
                    
                case .verify(.failure(_)):
                    return .none
                    
                case .binding:
                    return .none
            }
        }
    }
}
