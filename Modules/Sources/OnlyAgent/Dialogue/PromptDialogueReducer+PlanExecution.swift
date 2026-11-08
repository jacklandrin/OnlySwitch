//
//  PromptDialogueReducer+PlanExecution.swift
//  Modules
//

import ComposableArchitecture
import Extensions

@available(macOS 26.0, *)
extension PromptDialogueReducer {
    func reduceGeneratePlan(_ state: inout State, promptService: PromptDialogueService) -> Effect<Action> {
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
    }

    func reducePlanGenerated(_ state: inout State, plan: [ExecutionStep]) -> Effect<Action> {
        state.isPlanning = false
        state.executionPlan = plan
        state.isGenerating = false
        if state.executionMode == .hybrid {
            state.showPlanPreview = true
        } else if state.executionMode == .auto {
            return .send(.approvePlan)
        }
        return .none
    }

    func reducePlanGeneratedFailure(_ state: inout State, error: any Error) -> Effect<Action> {
        state.isPlanning = false
        state.errorMessage = error.localizedDescription
        state.isSuccess = false
        return .none
    }

    func reduceApprovePlan(_ state: inout State) -> Effect<Action> {
        state.showPlanPreview = false
        guard let plan = state.executionPlan,
              !plan.isEmpty else {
            return .none
        }
        state.currentStepIndex = 0
        return .send(.executeStep(0))
    }

    func reduceExecuteStep(_ state: inout State, stepIndex: Int, promptService: PromptDialogueService) -> Effect<Action> {
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
                        try await promptService.executeStep(step)
                    }
                )
            )
        }
    }

    func reduceStepCompleted(_ state: inout State, stepNumber: Int, result: StepResult) -> Effect<Action> {
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
    }

    func reduceStepCompletedFailure(
        _ state: inout State,
        stepNumber: Int,
        error: any Error,
        promptService: PromptDialogueService
    ) -> Effect<Action> {
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
                            return try await promptService.generateFix(
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
    }

    func reduceGenerateNextStep(_ state: inout State, promptService: PromptDialogueService) -> Effect<Action> {
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
                        return try await promptService.generateNextStep(
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
    }

    func reduceNextStepGenerated(_ state: inout State, step: ExecutionStep) -> Effect<Action> {
        guard var plan = state.executionPlan else {
            state.executionPlan = [step]
            state.currentStepIndex = 0
            return .send(.executeStep(0))
        }
        
        plan.append(step)
        state.executionPlan = plan
        state.currentStepIndex = plan.count - 1
        return .send(.executeStep(plan.count - 1))
    }

    func reduceNextStepGeneratedFailure(_ state: inout State) -> Effect<Action> {
        // No more steps needed or error generating
        state.isExecuting = false
        state.isSuccess = true
        return .none
    }

    func reduceStepRetried(_ state: inout State, stepNumber: Int, fixedStep: ExecutionStep) -> Effect<Action> {
        guard var plan = state.executionPlan,
              let stepIndex = plan.firstIndex(where: { $0.stepNumber == stepNumber }) else {
            return .none
        }
        
        plan[stepIndex] = fixedStep
        plan[stepIndex].status = .pending
        state.executionPlan = plan
        return .send(.executeStep(stepIndex))
    }

    func reduceStepRetriedFailure(_ state: inout State, error: any Error) -> Effect<Action> {
        state.errorMessage = error.localizedDescription
        state.isExecuting = false
        state.isSuccess = false
        return .none
    }

    func reduceRetryStep(
        _ state: inout State,
        stepIndex: Int,
        errorMessage: String,
        promptService: PromptDialogueService
    ) -> Effect<Action> {
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
                        return try await promptService.generateFix(
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
    }

    func reduceCancelExecution(_ state: inout State) -> Effect<Action> {
        state.isExecuting = false
        state.isPlanning = false
        state.thinkingText = ""
        state.executionPlan = nil
        state.currentStepIndex = -1
        state.executionHistory = []
        state.showPlanPreview = false
        return .none
    }
}
