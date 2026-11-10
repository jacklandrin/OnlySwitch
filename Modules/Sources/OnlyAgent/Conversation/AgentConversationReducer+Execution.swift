//
//  AgentConversationReducer+Execution.swift
//  Modules
//

import ComposableArchitecture
import Foundation

extension AgentConversationReducer {
    func reduceExecution(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case let .editStepCode(planID, stepID, code):
            guard state.runningPlanID != planID else { return .none }
            state.updatePlan(planID) { plan in
                guard let index = plan.steps.firstIndex(where: { $0.id == stepID }) else { return }
                plan.steps[index].code = code
                // An edited plan must run again before it can be saved.
                for stepIndex in plan.steps.indices {
                    plan.steps[stepIndex].status = .pending
                    plan.steps[stepIndex].output = nil
                    plan.steps[stepIndex].error = nil
                }
            }
            state.savedPlanIDs.remove(planID)
            return .none

        case let .runPlan(planID):
            guard !state.isBusy, state.plan(planID) != nil else { return .none }
            state.runningPlanID = planID
            state.updatePlan(planID) { plan in
                for index in plan.steps.indices {
                    plan.steps[index].status = .pending
                    plan.steps[index].output = nil
                    plan.steps[index].error = nil
                }
            }
            return runNextStep(&state, planID: planID)

        case let .stepFinished(planID, stepID, result):
            guard state.runningPlanID == planID else { return .none }
            state.passwordRequest = nil
            switch result {
            case let .success(output):
                state.updatePlan(planID) { plan in
                    guard let index = plan.steps.firstIndex(where: { $0.id == stepID }) else { return }
                    plan.steps[index].status = .succeeded
                    plan.steps[index].output = output
                }
                return runNextStep(&state, planID: planID)
            case let .failure(failure):
                state.updatePlan(planID) { plan in
                    guard let index = plan.steps.firstIndex(where: { $0.id == stepID }) else { return }
                    plan.steps[index].status = .failed
                    plan.steps[index].error = failure.message
                    Self.skipRemaining(&plan)
                }
                state.runningPlanID = nil
                return .none
            }

        case .stopRun:
            guard let planID = state.runningPlanID else { return .none }
            let answerPending = cancelPendingPassword(&state)
            state.updatePlan(planID) { plan in
                if let index = plan.steps.firstIndex(where: { $0.status == .running }) {
                    plan.steps[index].status = .stopped
                }
                Self.skipRemaining(&plan)
            }
            state.runningPlanID = nil
            return .merge(answerPending, .cancel(id: CancelID.execution))

        case let .passwordRequested(planID, request):
            guard state.runningPlanID == planID else { return .none }
            state.passwordRequest = request
            return .none

        case let .passwordSubmitted(password):
            guard let request = state.passwordRequest else { return .none }
            state.passwordRequest = nil
            let client = client
            return .run { _ in
                await client.answerPassword(request.id, password)
            }

        case .passwordCancelled:
            return cancelPendingPassword(&state)

        case let .askToFix(planID):
            guard !state.isBusy, state.plan(planID)?.hasFailed == true else { return .none }
            guard state.currentAIModel?.modelProvider != nil else {
                state.messages.append(AgentMessage(id: uuid(), role: .assistant, content: .notice(.selectModel)))
                return .none
            }
            state.messages.append(AgentMessage(id: uuid(), role: .user, content: .fixRequest))
            return startTurn(&state)

        case let .saveTapped(planID):
            guard !state.isBusy, let plan = state.plan(planID), plan.isSucceeded else { return .none }
            state.saveDraft = .init(planID: planID, name: plan.title)
            return .none

        case let .saveNameChanged(name):
            state.saveDraft?.name = name
            state.saveDraft?.error = nil
            return .none

        case .saveCancelled:
            state.saveDraft = nil
            return .none

        case .saveConfirmed:
            guard let draft = state.saveDraft, !draft.isSaving,
                  let plan = state.plan(draft.planID), plan.isSucceeded else {
                return .none
            }
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .none }
            state.saveDraft?.isSaving = true
            let steps = plan.steps
            let evolutionClient = evolutionClient
            return .run { send in
                do {
                    let askpassPath = EvolutionScriptComposer.needsAskpass(steps)
                        ? try await evolutionClient.installAskpass()
                        : nil
                    let command = EvolutionScriptComposer.compose(steps, askpassPath: askpassPath)
                    try await evolutionClient.saveButton(AgentEvolutionDraft(name: name, command: command))
                    await send(.saveFinished(.success(())))
                } catch {
                    await send(.saveFinished(.failure(AgentStepFailure(message: error.localizedDescription))))
                }
            }

        case .saveFinished(.success):
            if let planID = state.saveDraft?.planID {
                state.savedPlanIDs.insert(planID)
            }
            state.saveDraft = nil
            state.toast = .savedToEvolution
            let clock = clock
            return .run { send in
                try await clock.sleep(for: .seconds(2))
                await send(.toastDismissed)
            }
            .cancellable(id: CancelID.toast, cancelInFlight: true)

        case let .saveFinished(.failure(failure)):
            state.saveDraft?.isSaving = false
            state.saveDraft?.error = failure.message
            return .none

        case .toastDismissed:
            state.toast = nil
            return .none

        default:
            return .none
        }
    }

    private func runNextStep(_ state: inout State, planID: UUID) -> Effect<Action> {
        guard let plan = state.plan(planID),
              let index = plan.steps.firstIndex(where: { $0.status == .pending }) else {
            state.runningPlanID = nil
            return .none
        }
        let step = plan.steps[index]
        state.updatePlan(planID) { $0.steps[index].status = .running }
        let client = client
        return .run { send in
            let result: Result<String, AgentStepFailure>
            do {
                var output = ""
                for try await event in client.run(step.kind, step.code) {
                    switch event {
                    case let .passwordRequested(request):
                        await send(.passwordRequested(planID: planID, request: request))
                    case let .finished(text):
                        output = text
                    }
                }
                try Task.checkCancellation()
                result = .success(output)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                result = .failure(AgentStepFailure(message: error.localizedDescription))
            }
            await send(.stepFinished(planID: planID, stepID: step.id, result: result))
        }
        .cancellable(id: CancelID.execution, cancelInFlight: true)
    }

    /// Answers a pending sudo prompt with "cancelled" so the helper and the
    /// waiting step are released.
    func cancelPendingPassword(_ state: inout State) -> Effect<Action> {
        guard let request = state.passwordRequest else { return .none }
        state.passwordRequest = nil
        let client = client
        return .run { _ in
            await client.answerPassword(request.id, nil)
        }
    }

    private static func skipRemaining(_ plan: inout AgentPlan) {
        for index in plan.steps.indices where plan.steps[index].status == .pending {
            plan.steps[index].status = .skipped
        }
    }
}
