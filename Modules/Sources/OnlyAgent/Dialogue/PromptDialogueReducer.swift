//
//  PromptDialogueReducer.swift
//  Modules
//
//  Created by Bo Liu on 17.11.25.
//

import ComposableArchitecture
import Dependencies

@available(macOS 26.0, *)
@Reducer
public struct PromptDialogueReducer {
    @ObservableState
    public struct State {
        public var prompt: String = ""
        var appleScript: String = ""
        var isAgentMode: Bool = false
        var isGenerating: Bool = false
        var isExecuting: Bool = false
        var errorMessage: String? = nil
        var isSuccess: Bool? = nil
        var modelTags: [ModelProvider: [String]] = [:]
        var currentAIModel: CurrentAIModel? = nil
        var isPromptEmpty: Bool { prompt.isEmpty }
        var isAppleScriptEmpty: Bool { appleScript.isEmpty }
        var agentToggleDisabled: Bool { !(isPromptEmpty || isAppleScriptEmpty) || isGenerating || isExecuting }
        var sendButtonDisabled: Bool { isGenerating || isExecuting || isPromptEmpty }
        var shouldShowExecuteButton: Bool { !isAgentMode && !isExecuting && !isAppleScriptEmpty }
        var currentModelName: String? { currentAIModel?.model }
        
        public init(
            prompt: String = "",
            appleScript: String = "",
            isAgentMode: Bool = false,
        ) {
            self.prompt = prompt
            self.appleScript = appleScript
            self.isAgentMode = isAgentMode
        }
    }
    
    public init() {}
    
    public enum Action: BindableAction {
        case appear
        case selectAIModel(provider: String, model: String)
        case sendPrompt
        case generateAppleScript(TaskResult<String>)
        case executeAppleScript
        case finishExecution(TaskResult<Void>)
        case binding(BindingAction<State>)
    }
    
    @Dependency(\.promptDialogueService) var promptDialogueService
    @Dependency(\.openAIService) var openAIService
    @Shared(.ollamaModels) var ollamaModels: [OllamaTag]
    @Shared(.currentAIModel) var currentAIModel: CurrentAIModel?
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
                case .appear:
                    state.prompt = ""
                    state.appleScript = ""
                    state.errorMessage = nil
                    state.modelTags = [
                        .ollama: ollamaModels.map(\.model),
                        .openai: openAIService.models().map(\.model)
                    ]
                    state.currentAIModel = currentAIModel
                    return .none
                    
                case let .selectAIModel(provider, model):
                    state.currentAIModel = .init(provider: provider, model: model)
                    $currentAIModel.withLock { $0 = state.currentAIModel }
                    return .none
                    
                case .sendPrompt:
                    state.appleScript = ""
                    state.isGenerating = true
                    state.isSuccess = nil
                    let prompt = state.prompt
                    let isAgentMode = state.isAgentMode
                    guard let currentAIModel = state.currentAIModel else {
                        return .none
                    }
                    return .run { [prompt, isAgentMode, currentAIModel] send in
                        await send(
                            .generateAppleScript(
                                TaskResult {
                                    let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                                    return try await promptDialogueService.request(.purpose(prompt), modelProvider, currentAIModel.model, isAgentMode)
                                }
                            )
                        )
                    }
                    
                case .generateAppleScript(.success(let appleScript)):
                    state.appleScript = appleScript
                    state.isGenerating = false

                    let isAgentMode = state.isAgentMode
                    if isAgentMode {
                        guard let currentAIModel = state.currentAIModel else {
                            return .none
                        }
                        return .run { [isAgentMode, currentAIModel] send in
                            let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                            _ = try await promptDialogueService.request(.success, modelProvider, currentAIModel.model, isAgentMode)
                        }
                    } else {
                        return .none
                    }
                    
                case let .generateAppleScript(.failure(error)):
                    state.isGenerating = false
                    state.isSuccess = false
                    state.errorMessage = "\(error.localizedDescription)"
                    let isAgentMode = state.isAgentMode
                    
                    if isAgentMode {
                        return .none
                    } else {
                        guard let currentAIModel = state.currentAIModel else {
                            return .none
                        }
                        return .run { [isAgentMode, currentAIModel] send in
                            let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                            _ = try await promptDialogueService.request(.failure, modelProvider, currentAIModel.model, isAgentMode)
                        }
                    }
                    
                case .executeAppleScript:
                    state.isExecuting = true
                    let appleScript = state.appleScript
                    return .run { [appleScript] send in
                        await send(
                            .finishExecution(
                                TaskResult {
                                    try await promptDialogueService.execute(appleScript)
                                }
                            )
                        )
                    }
                    
                case .finishExecution(.success):
                    state.isExecuting = false
                    state.isSuccess = true
                    let isAgentMode = state.isAgentMode
                    guard let currentAIModel = state.currentAIModel else {
                        return .none
                    }
                    return .run { [isAgentMode, currentAIModel] send in
                        let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                        _ = try await promptDialogueService.request(.success, modelProvider, currentAIModel.model, isAgentMode)
                    }
                    
                case let .finishExecution(.failure(error)):
                    state.isExecuting = false
                    state.isSuccess = false
                    state.errorMessage = "\(error.localizedDescription)"
                    let isAgentMode = state.isAgentMode
                    guard let currentAIModel = state.currentAIModel else {
                        return .none
                    }
                    return .run { [isAgentMode, currentAIModel] send in
                        let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                        _ = try await promptDialogueService.request(.failure, modelProvider, currentAIModel.model, isAgentMode)
                    }
                    
                case .binding(\.prompt):
                    if state.prompt.isEmpty {
                        state.isSuccess = nil
                    }
                    return .none
                    
                case .binding:
                    return .none
            }
        }
    }
}

