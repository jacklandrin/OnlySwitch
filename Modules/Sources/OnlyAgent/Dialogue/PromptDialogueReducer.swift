//
//  PromptDialogueReducer.swift
//  Modules
//
//  Created by Bo Liu on 17.11.25.
//

import ComposableArchitecture
import Dependencies
import Extensions

@available(macOS 26.0, *)
@Reducer
public struct PromptDialogueReducer {
    @ObservableState
    public struct State: Equatable {
        public var prompt: String = ""
        public var isSuccess: Bool? = nil
        var appleScript: String = ""
        var isAgentMode: Bool = false
        var showAppleScriptEditor: Bool = true
        var isGenerating: Bool = false
        var isExecuting: Bool = false
        var errorMessage: String? = nil
        var modelTags: [ModelProvider: [String]] = [:]
        var currentAIModel: CurrentAIModel? = nil
        var opacity: Double = 1.0
        var blurRadius: Double = 0.0
        var isPromptEmpty: Bool { prompt.isEmpty }
        var isAppleScriptEmpty: Bool { appleScript.isEmpty }
        var agentToggleDisabled: Bool { !(isPromptEmpty || isAppleScriptEmpty) || isGenerating || isExecuting }
        var sendButtonDisabled: Bool { isGenerating || isExecuting || isPromptEmpty }
        var shouldShowExecuteButton: Bool { !isAgentMode && !isExecuting && !isAppleScriptEmpty }
        var currentModelName: String? { currentAIModel?.model }
        var shouldShowAppleScriptEditor: Bool { showAppleScriptEditor && !isAppleScriptEmpty && !isMultiStepMode }
        
        // Multi-step execution state
        var executionPlan: [ExecutionStep]? = nil
        var currentStepIndex: Int = -1
        var executionHistory: [StepResult] = []
        var isPlanning: Bool = false
        var executionMode: ExecutionMode = .hybrid
        var taskContext: TaskContext? = nil
        var showPlanPreview: Bool = false
        var isMultiStepMode: Bool = false
        var thinkingText: String = ""
        
        public init(
            prompt: String = "",
            appleScript: String = "",
            isAgentMode: Bool = false,
            showAppleScriptEditor: Bool = true,
        ) {
            self.prompt = prompt
            self.appleScript = appleScript
            self.isAgentMode = isAgentMode
            self.showAppleScriptEditor = showAppleScriptEditor
        }
    }
    
    public enum ExecutionMode: Equatable {
        case auto
        case interactive
        case hybrid
    }
    
    public init() {}
    
    public enum Action: BindableAction {
        case appear
        case loadModels(TaskResult<[ModelProvider: [String]]>)
        case selectAIModel(provider: String, model: String)
        case sendPrompt
        case receiveStreamEvent(ModelStreamEvent)
        case generateAppleScript(TaskResult<String>)
        case executeAppleScript
        case finishExecution(TaskResult<Void>)
        case disappear
        case binding(BindingAction<State>)
        
        // Multi-step execution actions
        case generatePlan
        case planGenerated(TaskResult<[ExecutionStep]>)
        case approvePlan
        case executeStep(Int)
        case stepCompleted(Int, TaskResult<StepResult>)
        case generateNextStep
        case nextStepGenerated(TaskResult<ExecutionStep>)
        case retryStep(Int, String)
        case stepRetried(Int, TaskResult<ExecutionStep>)
        case cancelExecution
        case updateExecutionMode(ExecutionMode)
    }
    
    @Dependency(\.promptDialogueService) var promptDialogueService
    @Dependency(\.modelProviderService) var modelProviderService
    @Shared(.ollamaModels) var ollamaModels: [OllamaTag]
    @Shared(.currentAIModel) var currentAIModel: CurrentAIModel?
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            let promptService = promptDialogueService
            let providerService = modelProviderService
            switch action {
                case .appear:
                    state.prompt = ""
                    state.appleScript = ""
                    state.thinkingText = ""
                    state.errorMessage = nil
                    state.modelTags = [
                        .ollama: ollamaModels.map(\.model)
                    ]
                    state.currentAIModel = currentAIModel
                    state.opacity = 1.0
                    state.blurRadius = 0.0
                    state.isSuccess = nil
                    state.isMultiStepMode = false
                    state.executionPlan = nil
                    return .run { send in
                        await send(
                            .loadModels(
                                TaskResult {
                                    let openaiModels = try await providerService.models(.openai)
                                    let codexModels = try await providerService.models(.codex)
                                    let geminiModels = try await providerService.models(.gemini)
                                    return [
                                        .openai: openaiModels.map(\.model),
                                        .codex: codexModels.map(\.model),
                                        .gemini: geminiModels.map(\.model)
                                    ]
                                }
                            )
                        )
                    }
                    
                case let .loadModels(.success(modelTags)):
                    state.modelTags.merge(modelTags) { (_, new) in new }
                    return .none
                    
                case .loadModels(.failure):
                    return .none
                    
                case let .selectAIModel(provider, model):
                    state.currentAIModel = .init(provider: provider, model: model)
                    $currentAIModel.withLock { $0 = state.currentAIModel }
                    return .none
                    
                case .sendPrompt:
                    // Check if this should be multi-step execution
                    let prompt = state.prompt
                    let isComplexTask = prompt.split(separator: " ").count > 10 || 
                                       prompt.lowercased().contains("and then") ||
                                       prompt.lowercased().contains("step by step") ||
                                       prompt.lowercased().contains("multiple")
                    
                    if isComplexTask && state.isAgentMode {
                        // Start multi-step execution
                        state.isGenerating = true
                        state.isMultiStepMode = true
                        state.isPlanning = true
                        state.executionPlan = nil
                        state.executionHistory = []
                        state.currentStepIndex = -1
                        state.thinkingText = ""
                        
                        guard let currentAIModel = state.currentAIModel else {
                            return .none
                        }
                        
                        let context = TaskContext(
                            originalPrompt: prompt,
                            goal: prompt,
                            constraints: [],
                            systemCapabilities: [
                                "AppleScript automation",
                                "File system operations",
                                "Application control",
                                "System settings"
                            ]
                        )
                        state.taskContext = context
                        
                        return .run { [prompt, context, currentAIModel] send in
                            await send(
                                .planGenerated(
                                    TaskResult {
                                        let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                                        return try await promptService.generatePlan(
                                            prompt,
                                            context,
                                            modelProvider,
                                            currentAIModel.model
                                        )
                                    }
                                )
                            )
                        }
                    } else {
                        // Single-step execution (existing flow)
                        state.appleScript = ""
                        state.thinkingText = ""
                        state.isGenerating = true
                        state.isSuccess = nil
                        state.isMultiStepMode = false
                        let isAgentMode = state.isAgentMode
                        guard let currentAIModel = state.currentAIModel else {
                            return .none
                        }
                        return .run { [prompt, isAgentMode, currentAIModel] send in
                            do {
                                let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                                let stream = try await promptService.requestStream(
                                    .purpose(prompt),
                                    modelProvider,
                                    currentAIModel.model,
                                    isAgentMode
                                )
                                
                                for try await event in stream {
                                    await send(.receiveStreamEvent(event))
                                }
                            } catch {
                                await send(.generateAppleScript(.failure(error)))
                            }
                        }
                    }
                    
                case let .receiveStreamEvent(event):
                    switch event {
                    case let .thinkingDelta(delta):
                        state.thinkingText += delta
                        return .none
                    case let .contentDelta(delta):
                        // Fallback behavior for providers without explicit thinking events.
                        state.thinkingText += delta
                        return .none
                    case let .completed(finalText):
                        state.thinkingText = ""
                        return .send(.generateAppleScript(.success(finalText)))
                    }
                    
                case .generateAppleScript(.success(let appleScript)):
                    state.appleScript = appleScript
                    state.thinkingText = ""
                    state.isGenerating = false

                    let isAgentMode = state.isAgentMode
                    if isAgentMode {
                        state.isSuccess = true
                        return .run { [appleScript] send in
                            await send(
                                .finishExecution(
                                    TaskResult {
                                        try await promptService.execute(appleScript)
                                    }
                                )
                            )
                        }
                    } else {
                        return .none
                    }
                    
                case let .generateAppleScript(.failure(error)):
                    state.thinkingText = ""
                    state.isGenerating = false
                    state.isSuccess = false
                    state.errorMessage = "\(error.localizedDescription)"
                    let isAgentMode = state.isAgentMode
                    
                    if isAgentMode {
                        state.isSuccess = false
                        return .none
                    } else {
                        guard let currentAIModel = state.currentAIModel else {
                            return .none
                        }
                        return .run { [isAgentMode, currentAIModel] send in
                            let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                            _ = try await promptService.request(.failure, modelProvider, currentAIModel.model, isAgentMode)
                        }
                    }
                    
                case .executeAppleScript:
                    state.isExecuting = true
                    let appleScript = state.appleScript
                    return .run { [appleScript] send in
                        await send(
                            .finishExecution(
                                TaskResult {
                                    try await promptService.execute(appleScript)
                                }
                            )
                        )
                    }
                    
                case .finishExecution(.success):
                    state.isExecuting = false
                    state.isSuccess = true
                    let isAgentMode = state.isAgentMode
                    guard !isAgentMode else {
                        return .none
                    }
                    guard let currentAIModel = state.currentAIModel else {
                        return .none
                    }
                    return .run { [isAgentMode, currentAIModel] send in
                        let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                        _ = try await promptService.request(.success, modelProvider, currentAIModel.model, isAgentMode)
                    }
                    
                case let .finishExecution(.failure(error)):
                    state.isExecuting = false
                    state.isSuccess = false
                    state.errorMessage = "\(error.localizedDescription)"
                    let isAgentMode = state.isAgentMode
                    guard !isAgentMode else {
                        return .none
                    }
                    guard let currentAIModel = state.currentAIModel else {
                        return .none
                    }
                    return .run { [isAgentMode, currentAIModel] send in
                        let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                        _ = try await promptService.request(.failure, modelProvider, currentAIModel.model, isAgentMode)
                    }
                    
                case .disappear:
                    state.thinkingText = ""
                    state.opacity = 0
                    state.blurRadius = 20.0
                    return .none
                    
                case .binding(\.prompt):
                    if state.prompt.isEmpty {
                        state.isSuccess = nil
                    }
                    return .none
                    
                case .binding:
                    return .none
                    
                // Multi-step execution handlers
                case .generatePlan:
                    return reduceGeneratePlan(&state, promptService: promptService)
                    
                case .planGenerated(.success(let plan)):
                    return reducePlanGenerated(&state, plan: plan)
                    
                case .planGenerated(.failure(let error)):
                    return reducePlanGeneratedFailure(&state, error: error)
                    
                case .approvePlan:
                    return reduceApprovePlan(&state)
                    
                case .executeStep(let stepIndex):
                    return reduceExecuteStep(&state, stepIndex: stepIndex, promptService: promptService)
                    
                case .stepCompleted(let stepNumber, .success(let result)):
                    return reduceStepCompleted(&state, stepNumber: stepNumber, result: result)
                    
                case .stepCompleted(let stepNumber, .failure(let error)):
                    return reduceStepCompletedFailure(&state, stepNumber: stepNumber, error: error, promptService: promptService)
                    
                case .generateNextStep:
                    return reduceGenerateNextStep(&state, promptService: promptService)
                    
                case .nextStepGenerated(.success(let step)):
                    return reduceNextStepGenerated(&state, step: step)
                    
                case .nextStepGenerated(.failure):
                    return reduceNextStepGeneratedFailure(&state)
                    
                case .stepRetried(let stepNumber, .success(let fixedStep)):
                    return reduceStepRetried(&state, stepNumber: stepNumber, fixedStep: fixedStep)
                    
                case .stepRetried(_, .failure(let error)):
                    return reduceStepRetriedFailure(&state, error: error)
                    
                case .retryStep(let stepIndex, let errorMessage):
                    return reduceRetryStep(&state, stepIndex: stepIndex, errorMessage: errorMessage, promptService: promptService)
                    
                case .cancelExecution:
                    return reduceCancelExecution(&state)
                    
                case .updateExecutionMode(let mode):
                    state.executionMode = mode
                    return .none
            }
        }
    }
}
