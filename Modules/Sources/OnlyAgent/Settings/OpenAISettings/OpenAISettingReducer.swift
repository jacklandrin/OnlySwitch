//
//  OpenAISettingReducer.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import ComposableArchitecture
import Dependencies
import Foundation

@available(macOS 26.0, *)
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
        case getModels(TaskResult<[String]>)
        case verify(TaskResult<Bool>)
        case binding(BindingAction<State>)
    }
    
    @Dependency(\.modelProviderService) var modelProviderService
    @Shared(.openAIAPIKey) var apiKey: String = ""
    @Shared(.openAIHost) var host
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
                case .appear:
                    state.apiKey = apiKey
                    state.host = host
                    return .run { send in
                        await send(
                            .getModels(
                                TaskResult {
                                    try await modelProviderService.models(.openai).map(\.model)
                                }
                            )
                        )
                    }
            
                case .check:
                    modelProviderService.setAPIKey(.openai, state.apiKey, state.host)
                    $apiKey.withLock { $0 = state.apiKey }
                    $host.withLock { $0 = state.host }
                    return .run { send in
                       await send(
                            .verify(
                                TaskResult {
                                    await modelProviderService.test(.openai)
                                }
                            )
                        )
                    }
                    
                case .getModels(.success(let models)):
                    state.models = models
                    return .none
                    
                case .getModels(.failure):
                    return .none
                    
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
