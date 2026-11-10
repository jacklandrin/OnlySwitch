//
//  AgentConversationReducer.swift
//  Modules
//

import ComposableArchitecture
import Extensions
import Foundation
import OSLog

extension SharedKey where Self == AppStorageKey<AgentExecutionMode>.Default {
    public static var agentExecutionMode: Self {
        Self[.appStorage("onlyAgentExecutionMode"), default: .preview]
    }
}

public enum AgentToast: Equatable, Sendable {
    case savedToEvolution
}

@Reducer
public struct AgentConversationReducer {
    @ObservableState
    public struct State: Equatable {
        public struct SaveDraft: Equatable {
            public var planID: UUID
            public var name: String
            public var isSaving = false
            public var error: String?

            public init(planID: UUID, name: String, isSaving: Bool = false, error: String? = nil) {
                self.planID = planID
                self.name = name
                self.isSaving = isSaving
                self.error = error
            }
        }

        public var draft = ""
        public var messages: IdentifiedArrayOf<AgentMessage> = []
        public var isGenerating = false
        public var thinkingText = ""
        public var modelTags: [ModelProvider: [String]] = [:]
        /// Starter prompts for an empty conversation, based on the Mac's current state.
        public var suggestions: [AgentSuggestion] = []
        public var runningPlanID: UUID?
        public var saveDraft: SaveDraft?
        public var savedPlanIDs: Set<UUID> = []
        public var toast: AgentToast?
        /// sudo is waiting for a password for the running step. The password
        /// itself is never stored in state.
        public var passwordRequest: AgentPasswordRequest?
        /// Identifies the conversation to providers that keep threads (Codex).
        public var conversationID = UUID()
        /// Read on appear and written only by `selectAIModel` (upgrade compatibility).
        @Shared public var currentAIModel: CurrentAIModel?
        @Shared public var executionMode: AgentExecutionMode

        public init(
            currentAIModel: Shared<CurrentAIModel?> = Shared(.currentAIModel),
            executionMode: Shared<AgentExecutionMode> = Shared(.agentExecutionMode)
        ) {
            _currentAIModel = currentAIModel
            _executionMode = executionMode
        }

        public var isRunning: Bool { runningPlanID != nil }
        public var isBusy: Bool { isGenerating || isRunning }
        public var canSend: Bool {
            !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        /// The window may hide on an outside click only when nothing is in flight.
        public var canDismiss: Bool { !isBusy && saveDraft == nil && passwordRequest == nil }

        public func plan(_ id: UUID) -> AgentPlan? {
            for message in messages {
                if case let .plan(plan) = message.content, plan.id == id {
                    return plan
                }
            }
            return nil
        }

        public mutating func updatePlan(_ id: UUID, _ body: (inout AgentPlan) -> Void) {
            guard let index = messages.firstIndex(where: {
                if case let .plan(plan) = $0.content { return plan.id == id }
                return false
            }), case var .plan(plan) = messages[index].content else {
                return
            }
            body(&plan)
            messages[index].content = .plan(plan)
        }
    }

    public enum Action: BindableAction {
        case appear
        case modelsLoaded([ModelProvider: [String]])
        case systemInfoLoaded(AgentSystemInfo)
        case selectAIModel(provider: ModelProvider, model: String)
        case setExecutionMode(AgentExecutionMode)
        case binding(BindingAction<State>)
        case sendTapped
        case suggestionTapped(String)
        case answerChanged(messageID: UUID, questionID: UUID, answer: String)
        case submitAnswers(messageID: UUID)
        case streamEvent(ModelStreamEvent)
        case replyFinished(String)
        case replyFailed(String)
        case stopGenerating
        case newConversation

        case editStepCode(planID: UUID, stepID: UUID, code: String)
        case runPlan(UUID)
        case stepFinished(planID: UUID, stepID: UUID, result: Result<String, AgentStepFailure>)
        case stopRun
        case passwordRequested(planID: UUID, request: AgentPasswordRequest)
        case passwordSubmitted(String)
        case passwordCancelled
        case askToFix(UUID)
        case saveTapped(UUID)
        case saveNameChanged(String)
        case saveConfirmed
        case saveCancelled
        case saveFinished(Result<Void, AgentStepFailure>)
        case toastDismissed
    }

    enum CancelID {
        case generation
        case execution
        case toast
    }

    @Dependency(\.agentConversationClient) var client
    @Dependency(\.agentEvolutionClient) var evolutionClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.uuid) var uuid

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .appear:
                let client = client
                return .run { send in
                    // Local state first so suggestions appear before slow model listing.
                    await send(.systemInfoLoaded(await client.systemInfo()))
                    await send(.modelsLoaded(await client.availableModels()))
                }

            case let .systemInfoLoaded(info):
                state.suggestions = AgentSuggestion.make(for: info)
                return .none

            case let .modelsLoaded(tags):
                // Never touches `currentAIModel`: a missing or offline model
                // must not erase the user's stored selection.
                state.modelTags = tags
                return .none

            case let .selectAIModel(provider, model):
                state.$currentAIModel.withLock {
                    $0 = CurrentAIModel(provider: provider.rawValue, model: model)
                }
                return .none

            case let .setExecutionMode(mode):
                state.$executionMode.withLock { $0 = mode }
                return .none

            case .binding:
                return .none

            case .sendTapped:
                guard state.canSend else { return .none }
                guard state.currentAIModel?.modelProvider != nil else {
                    state.messages.append(AgentMessage(id: uuid(), role: .assistant, content: .notice(.selectModel)))
                    return .none
                }
                let text = state.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                state.draft = ""
                state.messages.append(AgentMessage(id: uuid(), role: .user, content: .text(text)))
                return startTurn(&state)

            case let .suggestionTapped(text):
                state.draft = text
                return .send(.sendTapped)

            case let .answerChanged(messageID, questionID, answer):
                guard case .questions(var questions, answered: false) = state.messages[id: messageID]?.content,
                      let index = questions.firstIndex(where: { $0.id == questionID }) else {
                    return .none
                }
                questions[index].answer = answer
                state.messages[id: messageID]?.content = .questions(questions, answered: false)
                return .none

            case let .submitAnswers(messageID):
                guard !state.isBusy,
                      state.messages.last?.id == messageID,
                      case let .questions(questions, answered: false) = state.messages[id: messageID]?.content,
                      questions.allSatisfy({ !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    return .none
                }
                guard state.currentAIModel?.modelProvider != nil else {
                    state.messages.append(AgentMessage(id: uuid(), role: .assistant, content: .notice(.selectModel)))
                    return .none
                }
                state.messages[id: messageID]?.content = .questions(questions, answered: true)
                return startTurn(&state)

            case let .streamEvent(event):
                switch event {
                case let .thinkingDelta(delta), let .contentDelta(delta):
                    state.thinkingText += delta
                case .completed:
                    break
                }
                return .none

            case let .replyFinished(text):
                state.isGenerating = false
                state.thinkingText = ""
                let reply = AgentReplyParser.parse(text, makeID: { uuid() })
                switch reply {
                case let .questions(questions):
                    state.messages.append(AgentMessage(id: uuid(), role: .assistant, content: .questions(questions, answered: false)))
                    return .none
                case let .message(message):
                    state.messages.append(AgentMessage(id: uuid(), role: .assistant, content: .text(message)))
                    return .none
                case let .plan(plan):
                    state.messages.append(AgentMessage(id: uuid(), role: .assistant, content: .plan(plan)))
                    return state.executionMode == .direct ? .send(.runPlan(plan.id)) : .none
                }

            case let .replyFailed(message):
                state.isGenerating = false
                state.thinkingText = ""
                state.messages.append(AgentMessage(id: uuid(), role: .assistant, content: .error(message)))
                return .none

            case .stopGenerating:
                state.isGenerating = false
                state.thinkingText = ""
                return .cancel(id: CancelID.generation)

            case .newConversation:
                state.messages = []
                state.draft = ""
                state.isGenerating = false
                state.thinkingText = ""
                state.runningPlanID = nil
                state.saveDraft = nil
                state.conversationID = uuid()
                let client = client
                return .merge(
                    .cancel(id: CancelID.generation),
                    .cancel(id: CancelID.execution),
                    cancelPendingPassword(&state),
                    .run { send in
                        await send(.systemInfoLoaded(await client.systemInfo()))
                    }
                )

            case .editStepCode, .runPlan, .stepFinished, .stopRun, .askToFix,
                 .passwordRequested, .passwordSubmitted, .passwordCancelled,
                 .saveTapped, .saveNameChanged, .saveConfirmed, .saveCancelled,
                 .saveFinished, .toastDismissed:
                return reduceExecution(&state, action)
            }
        }
    }

    func startTurn(_ state: inout State) -> Effect<Action> {
        guard let current = state.currentAIModel, let provider = current.modelProvider else {
            return .none
        }
        state.isGenerating = true
        state.thinkingText = ""
        let client = client
        let model = current.model
        let prompt = AgentPromptBuilder.prompt(for: Array(state.messages))
        let conversationID = state.conversationID
        return .run { send in
            // Collected fresh each turn: appearance, displays etc. may have changed.
            let systemInfo = await client.systemInfo()
            let request = ModelGenerationRequest(
                provider: provider,
                model: model,
                purpose: .agent,
                systemInstructions: AgentPromptBuilder.systemInstructions(systemInfo: systemInfo),
                prompt: prompt,
                maximumOutputTokens: 4096,
                conversationID: conversationID
            )
            var accumulated = ""
            var finalText: String?
            for try await event in try await client.stream(request) {
                switch event {
                case let .contentDelta(delta):
                    accumulated += delta
                    await send(.streamEvent(event))
                case .thinkingDelta:
                    await send(.streamEvent(event))
                case let .completed(text):
                    finalText = text.isEmpty ? accumulated : text
                }
            }
            await send(.replyFinished(finalText ?? accumulated))
        } catch: { error, send in
            guard !(error is CancellationError) else { return }
            Logger.onlyAgentDebug.error("Only Agent request failed: \(error)")
            await send(.replyFailed(error.localizedDescription))
        }
        .cancellable(id: CancelID.generation, cancelInFlight: true)
    }
}

public struct AgentStepFailure: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}
