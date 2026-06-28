//
//  ClaudeSettingReducer.swift
//  Modules
//
//  Created by Louis Saks on 23.06.26.
//

import ComposableArchitecture
import Dependencies
import Foundation

@available(macOS 26.0, *)
@Reducer
public struct ClaudeSettingReducer {
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
    @Shared(.claudeAPIKey) var apiKey: String = ""

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .appear:
                state.apiKey = apiKey
                let service = modelProviderService
                return .run { send in
                    await send(
                        .getModels(
                            TaskResult {
                                try await service.models(.claude).map(\.model)
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
                modelProviderService.setAPIKey(.claude, state.apiKey, "")
                $apiKey.withLock { $0 = state.apiKey }
                let service = modelProviderService
                return .run { send in
                    await send(
                        .verify(
                            TaskResult {
                                await service.test(.claude)
                            }
                        )
                    )
                }

            case let .verify(.success(result)):
                state.isVerifying = false
                state.verified = result
                return .none

            case .verify(.failure):
                state.isVerifying = false
                state.verified = false
                return .none

            case .binding:
                return .none
            }
        }
    }
}
