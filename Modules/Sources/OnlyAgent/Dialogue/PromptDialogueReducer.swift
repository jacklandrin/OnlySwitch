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
        
        // Multi-step execution state
        var executionPlan: [ExecutionStep]? = nil
        var currentStepIndex: Int = -1
        var executionHistory: [StepResult] = []
        var isPlanning: Bool = false
        var executionMode: ExecutionMode = .hybrid
        var taskContext: TaskContext? = nil
        var showPlanPreview: Bool = false
        var isMultiStepMode: Bool = false
        
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
            switch action {
                case .appear:
                    state.prompt = ""
                    state.appleScript = ""
                    state.errorMessage = nil
                    state.modelTags = [
                        .ollama: ollamaModels.map(\.model)
                    ]
                    state.currentAIModel = currentAIModel
                    state.opacity = 1.0
                    state.blurRadius = 0.0
                    state.isSuccess = nil
                    return .run { send in
                        await send(
                            .loadModels(
                                TaskResult {
                                    let openaiModels = try await modelProviderService.models(.openai)
                                    let geminiModels = try await modelProviderService.models(.gemini)
                                    return [
                                        .openai: openaiModels.map(\.model),
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
                                        return try await promptDialogueService.generatePlan(
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
                        state.isGenerating = true
                        state.isSuccess = nil
                        state.isMultiStepMode = false
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
                    }
                    
                case .generateAppleScript(.success(let appleScript)):
                    state.appleScript = appleScript
                    state.isGenerating = false

                    let isAgentMode = state.isAgentMode
                    if isAgentMode {
                        state.isSuccess = true
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
                        state.isSuccess = false
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
                    
                case .disappear:
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
                    state.isPlanning = true
                    let prompt = state.prompt
                    guard let currentAIModel = state.currentAIModel,
                          let context = state.taskContext else {
                        return .none
                    }
                    return .run { [prompt, context, currentAIModel] send in
                        await send(
                            .planGenerated(
                                TaskResult {
                                    let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                                    return try await promptDialogueService.generatePlan(
                                        prompt,
                                        context,
                                        modelProvider,
                                        currentAIModel.model
                                    )
                                }
                            )
                        )
                    }
                    
                case .planGenerated(.success(let plan)):
                    state.isPlanning = false
                    state.executionPlan = plan
                    state.isGenerating = false
                    if state.executionMode == .hybrid {
                        state.showPlanPreview = true
                    } else if state.executionMode == .auto {
                        return .send(.approvePlan)
                    }
                    return .none
                    
                case .planGenerated(.failure(let error)):
                    state.isPlanning = false
                    state.errorMessage = error.localizedDescription
                    state.isSuccess = false
                    return .none
                    
                case .approvePlan:
                    state.showPlanPreview = false
                    guard let plan = state.executionPlan,
                          !plan.isEmpty else {
                        return .none
                    }
                    state.currentStepIndex = 0
                    return .send(.executeStep(0))
                    
                case .executeStep(let stepIndex):
                    guard let plan = state.executionPlan,
                          stepIndex < plan.count else {
                        return .none
                    }
                    
                    var updatedPlan = plan
                    updatedPlan[stepIndex].status = .executing
                    state.executionPlan = updatedPlan
                    
                    let step = plan[stepIndex]
                    return .run { [step, stepIndex] send in
                        // Add 0.2s delay between steps (except for the first step)
                        if stepIndex > 0 {
                            try? await Task.sleep(second: 0.2) // 0.2 seconds
                        }
                        
                        await send(
                            .stepCompleted(
                                step.stepNumber,
                                TaskResult {
                                    try await promptDialogueService.executeStep(step)
                                }
                            )
                        )
                    }
                    
                case .stepCompleted(let stepNumber, .success(let result)):
                    guard var plan = state.executionPlan,
                          let stepIndex = plan.firstIndex(where: { $0.stepNumber == stepNumber }) else {
                        return .none
                    }
                    
                    plan[stepIndex].status = .completed
                    plan[stepIndex].result = result
                    state.executionPlan = plan
                    state.executionHistory.append(result)
                    
                    if var context = state.taskContext {
                        context.executionHistory.append(result)
                        state.taskContext = context
                    }
                    
                    // Check if all steps are completed
                    if plan.allSatisfy({ $0.status == .completed || $0.status == .skipped }) {
                        state.isExecuting = false
                        state.isSuccess = true
                        return .none
                    }
                    
                    // Generate next step adaptively or proceed to next planned step
                    if state.executionMode == .auto || state.executionMode == .hybrid {
                        let nextIndex = stepIndex + 1
                        if nextIndex < plan.count {
                            state.currentStepIndex = nextIndex
                            return .send(.executeStep(nextIndex))
                        } else {
                            // All planned steps done, check if goal achieved
                            return .send(.generateNextStep)
                        }
                    }
                    
                    return .none
                    
                case .stepCompleted(let stepNumber, .failure(let error)):
                    guard var plan = state.executionPlan,
                          let stepIndex = plan.firstIndex(where: { $0.stepNumber == stepNumber }) else {
                        state.errorMessage = error.localizedDescription
                        state.isExecuting = false
                        state.isSuccess = false
                        return .none
                    }
                    
                    plan[stepIndex].status = .failed
                    state.executionPlan = plan
                    
                    // Handle error with retry strategy
                    let step = plan[stepIndex]
                    guard let context = state.taskContext,
                          let currentAIModel = state.currentAIModel else {
                        state.errorMessage = error.localizedDescription
                        state.isExecuting = false
                        state.isSuccess = false
                        return .none
                    }
                    
                    let planCount = plan.count
                    return .run { [step, error, context, currentAIModel, stepNumber, stepIndex, planCount] send in
                        let errorHandler = ErrorHandler.shared
                        let strategy = await errorHandler.handleStepError(
                            step: step,
                            error: error,
                            context: context
                        )
                        
                        switch strategy {
                        case .fixAndRetry:
                            await send(
                                .stepRetried(
                                    stepNumber,
                                    TaskResult {
                                        let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                                        return try await promptDialogueService.generateFix(
                                            step,
                                            error.localizedDescription,
                                            context,
                                            modelProvider,
                                            currentAIModel.model
                                        )
                                    }
                                )
                            )
                        case .skipAndContinue:
                            if stepIndex + 1 < planCount {
                                await send(.executeStep(stepIndex + 1))
                            } else {
                                // No more steps, execution complete
                                await send(.cancelExecution)
                            }
                        case .stopExecution:
                            await send(.cancelExecution)
                        case .immediateRetry:
                            await send(.executeStep(stepIndex))
                        }
                    }
                    
                case .generateNextStep:
                    guard let context = state.taskContext,
                          let currentAIModel = state.currentAIModel else {
                        return .none
                    }
                    
                    let remainingGoal = context.goal // Can be enhanced to track remaining goals
                    return .run { [context, remainingGoal, currentAIModel] send in
                        await send(
                            .nextStepGenerated(
                                TaskResult {
                                    let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                                    return try await promptDialogueService.generateNextStep(
                                        context.executionHistory,
                                        remainingGoal,
                                        context,
                                        modelProvider,
                                        currentAIModel.model
                                    )
                                }
                            )
                        )
                    }
                    
                case .nextStepGenerated(.success(let step)):
                    guard var plan = state.executionPlan else {
                        state.executionPlan = [step]
                        state.currentStepIndex = 0
                        return .send(.executeStep(0))
                    }
                    
                    plan.append(step)
                    state.executionPlan = plan
                    state.currentStepIndex = plan.count - 1
                    return .send(.executeStep(plan.count - 1))
                    
                case .nextStepGenerated(.failure):
                    // No more steps needed or error generating
                    state.isExecuting = false
                    state.isSuccess = true
                    return .none
                    
                case .stepRetried(let stepNumber, .success(let fixedStep)):
                    guard var plan = state.executionPlan,
                          let stepIndex = plan.firstIndex(where: { $0.stepNumber == stepNumber }) else {
                        return .none
                    }
                    
                    plan[stepIndex] = fixedStep
                    plan[stepIndex].status = .pending
                    state.executionPlan = plan
                    return .send(.executeStep(stepIndex))
                    
                case .stepRetried(_, .failure(let error)):
                    state.errorMessage = error.localizedDescription
                    state.isExecuting = false
                    state.isSuccess = false
                    return .none
                    
                case .retryStep(let stepIndex, let errorMessage):
                    guard let plan = state.executionPlan,
                          stepIndex < plan.count,
                          let context = state.taskContext,
                          let currentAIModel = state.currentAIModel else {
                        return .none
                    }
                    
                    let step = plan[stepIndex]
                    return .run { [step, errorMessage, context, currentAIModel] send in
                        await send(
                            .stepRetried(
                                step.stepNumber,
                                TaskResult {
                                    let modelProvider = ModelProvider(rawValue: currentAIModel.provider) ?? .ollama
                                    return try await promptDialogueService.generateFix(
                                        step,
                                        errorMessage,
                                        context,
                                        modelProvider,
                                        currentAIModel.model
                                    )
                                }
                            )
                        )
                    }
                    
                case .cancelExecution:
                    state.isExecuting = false
                    state.isPlanning = false
                    state.executionPlan = nil
                    state.currentStepIndex = -1
                    state.executionHistory = []
                    state.showPlanPreview = false
                    return .none
                    
                case .updateExecutionMode(let mode):
                    state.executionMode = mode
                    return .none
            }
        }
    }
}

