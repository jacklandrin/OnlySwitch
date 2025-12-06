//
//  GeminiSettingReducer.swift
//  Modules
//
//  Created by Bo Liu on 06.12.25.
//

import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
public struct GeminiSettingReducer {
    @ObservableState
    public struct State: Equatable {
        public var apiKey: String = ""
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
    
    @Dependency(\.geminiService) var geminiService
    @Shared(.geminiAPIKey) var apiKey
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
                case .appear:
                    state.models = geminiService.models().map(\.model)
                    state.apiKey = apiKey
                    return .none
            
                case .check:
                    geminiService.setAPIKey(state.apiKey)
                    $apiKey.withLock { $0 = state.apiKey }
                    return .run { send in
                       await send(
                            .verify(
                                TaskResult {
                                    await geminiService.test()
                                }
                            )
                        )
                    }
                    
                case let .verify(.success(result)):
                    state.verified = result
                    return .none
                    
                case .verify(.failure(_)):
                    state.verified = false
                    return .none
                    
                case .binding:
                    return .none
            }
        }
    }
}

