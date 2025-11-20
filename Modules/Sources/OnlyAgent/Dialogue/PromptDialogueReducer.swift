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
        var prompt: String = ""
        var appleScript: String = ""
        var isAgentMode: Bool = false
        var isGenerating: Bool = false
        var isExecuting: Bool = false
        var errorMessage: String? = nil
        var isSuccess: Bool? = nil
        var modelTags: IdentifiedArrayOf<OllamaTag> = []
        var currentAIModel: String? = nil
        var isPromptEmpty: Bool { prompt.isEmpty }
        var isAppleScriptEmpty: Bool { appleScript.isEmpty }
        var sendButtonDisabled: Bool { isGenerating || isExecuting || isPromptEmpty }
        var shouldShowExecuteButton: Bool { !isAgentMode && !isExecuting && !isAppleScriptEmpty }
        
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
        case selectAIModel(String)
        case sendPrompt
        case generateAppleScript(TaskResult<String>)
        case executeAppleScript
        case finishExecution(TaskResult<Void>)
        case binding(BindingAction<State>)
    }
    
    @Dependency(\.promptDialogueService) var promptDialogueService
    @Shared(.ollamaModels) var ollamaModels: [OllamaTag]
    @Shared(.currentAIModel) var currentAIModel: String?
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
                case .appear:
                    state.prompt = ""
                    state.appleScript = ""
                    state.errorMessage = nil
                    state.modelTags = IdentifiedArray(uniqueElements: ollamaModels)
                    state.currentAIModel = currentAIModel
                    return .none
                    
                case let .selectAIModel(model):
                    state.currentAIModel = model
                    $currentAIModel.withLock { $0 = model }
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
                                    try await promptDialogueService.request(prompt, .ollama, currentAIModel, isAgentMode)
                                }
                            )
                        )
                    }
                    
                case .generateAppleScript(.success(let appleScript)):
                    state.appleScript = appleScript
                    state.isGenerating = false
                    return .none
                    
                case let .generateAppleScript(.failure(error)):
                    state.isGenerating = false
                    state.isSuccess = false
                    state.errorMessage = "\(error.localizedDescription)"
                    return .none
                    
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
                    return .none
                    
                case let .finishExecution(.failure(error)):
                    state.isExecuting = false
                    state.isSuccess = false
                    state.errorMessage = "\(error.localizedDescription)"
                    return .none
                    
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

