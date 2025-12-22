//
//  GeminiSettingReducer.swift
//  Modules
//
//  Created by Bo Liu on 06.12.25.
//

import ComposableArchitecture
import Dependencies
import Foundation

@available(macOS 26.0, *)
@Reducer
public struct GeminiSettingReducer {
    @ObservableState
    public struct State: Equatable {
        public var apiKey: String = ""
        public var models: [String] = []
        public var verified: Bool? = nil
        public var isVerifying: Bool = false
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
    @Shared(.geminiAPIKey) var apiKey: String = ""
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
                case .appear:
                    state.apiKey = apiKey
                    return .run { send in
                        await send(
                            .getModels(
                                TaskResult {
                                    try await modelProviderService.models(.gemini).map(\.model)
                                }
                            )
                        )
                    }
                    
                case .getModels(.success(let models)):
                    state.models = models
                    return .none
                    
                case .getModels(.failure):
                    return .none
            
                case .check:
                    state.isVerifying = true
                    modelProviderService.setAPIKey(.gemini, state.apiKey, "")
                    $apiKey.withLock { $0 = state.apiKey }
                    return .run { send in
                       await send(
                            .verify(
                                TaskResult {
                                    await modelProviderService.test(.gemini)
                                }
                            )
                        )
                    }
                    
                case let .verify(.success(result)):
                    state.isVerifying = false
                    state.verified = result
                    return .none
                    
                case .verify(.failure(_)):
                    state.isVerifying = false
                    state.verified = false
                    return .none
                    
                case .binding:
                    return .none
            }
        }
    }
}

